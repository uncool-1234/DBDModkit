// DBD profile extension for Suzie. All DBD specific code of the profile lives here (everything else is data):
//  1. dbd.variant_configurator: the game serializes its variant configurator struct RAW (no property header): object reference, FString, tag.
//  2. dbd.material_instance_trailing_variants: after the reflected part of every cooked MaterialInstance export the game appends a count and
//     that many raw variant configurators.
//  3. dbd.bark_node_template: BhvrBarkNodeTemplate (16 bytes in memory, no reflected members) is a hand serialized inline object:
//     int32 bHasNode; if set: class package index, then that class instance's own unversioned property data inline, with NO serial size.
//     Because there is no size it cannot be skipped, it has to be decoded: a transient instance is created and read with
//     UObject::SerializeScriptProperties (format: FBhvrBarkNodeTemplate.cs of CUE4Parse (https://github.com/FabianFG/CUE4Parse), verified on BarkRuleDB bytes).
//  4. Native thunks of KismetMathLibrary and KismetSystemLibrary functions whose game signatures the stock classes lack or differ from.
// 1-3 are bound to types/classes by data: load/native_ops.json and load/skip.json of the profile; 4 by the function path (Register).
#include "SuzieExtension.h"

#include "GameplayTagContainer.h"
#include "Kismet/KismetMathLibrary.h"
#include "Kismet/KismetSystemLibrary.h"
#include "Modules/ModuleManager.h"
#include "Features/IModularFeatures.h"
#include "Serialization/Archive.h"
#include "UObject/Package.h"
#include "UObject/GarbageCollection.h"
#include "UObject/Script.h"
#include "UObject/ScriptMacros.h"
#include "UObject/UObjectGlobals.h"

DEFINE_LOG_CATEGORY_STATIC(LogDbdModkitGame, Log, All);

/** C++ twin of the generated struct /Script/Engine.BHVRVariantConfigurator (members in the game's order: object, string, tag). */
struct FDbdVariantConfigurator
{
	TObjectPtr<UObject> VariantGenerator = nullptr;
	FString VariantUniqueName;
	FGameplayTag VariantTag;

	bool Serialize(FArchive& Ar)
	{
		UObject* Generator = VariantGenerator;
		Ar << Generator;
		if (Ar.IsLoading())
		{
			VariantGenerator = Generator;
		}
		Ar << VariantUniqueName;
		Ar << VariantTag;
		return true;
	}
};

template <>
struct TStructOpsTypeTraits<FDbdVariantConfigurator> : public TStructOpsTypeTraitsBase2<FDbdVariantConfigurator>
{
	enum
	{
		WithSerializer = true,
	};
};

/**
 * C++ twin of the generated struct /Script/BhvrBark.BhvrBarkNodeTemplate: 16 bytes, alignment 8, no reflected members.
 * On disk: int32 bHasNode; if set: package index of a CLASS (a BhvrBarkNode subclass), then the instance's properties inline in the
 * unversioned format of that class, no serial size. The twin keeps the instance (a transient object) in the first 8 bytes and reports it to the GC.
 */
struct FDbdBarkNodeTemplate
{
	UObject* Node = nullptr;
	uint64 Reserved = 0;

	bool Serialize(FArchive& Ar)
	{
		if (Ar.IsLoading())
		{
			Node = nullptr;
			bool bHasNode = false;
			Ar << bHasNode;
			if (!bHasNode)
			{
				return true;
			}
			UObject* TypeObject = nullptr;
			Ar << TypeObject;
			UClass* NodeClass = Cast<UClass>(TypeObject);
			if (!NodeClass)
			{
				if (TypeObject)
				{
					// Not expected (seen in the data: always classes). No size is stored, so the rest cannot be skipped.
					UE_LOG(LogDbdModkitGame, Error, TEXT("%s: bark node type %s is not a class, archive marked as errored"), *Ar.GetArchiveName(), *TypeObject->GetPathName());
					Ar.SetError();
				}
				return true; // a null type has no data
			}
			Node = NewObject<UObject>(GetTransientPackage(), NodeClass);
			Node->SerializeScriptProperties(Ar);
		}
		else if (Ar.IsSaving())
		{
			bool bHasNode = Node != nullptr;
			Ar << bHasNode;
			if (bHasNode)
			{
				UObject* TypeObject = Node->GetClass();
				Ar << TypeObject;
				Node->SerializeScriptProperties(Ar);
			}
		}
		return true;
	}

	void AddStructReferencedObjects(FReferenceCollector& Collector)
	{
		Collector.AddReferencedObject(Node);
	}
};
static_assert(sizeof(FDbdBarkNodeTemplate) == 16, "must match the game's struct size");

template <>
struct TStructOpsTypeTraits<FDbdBarkNodeTemplate> : public TStructOpsTypeTraitsBase2<FDbdBarkNodeTemplate>
{
	enum
	{
		WithSerializer = true,
		WithAddStructReferencedObjects = true,
		WithZeroConstructor = true, // all-zero is a valid empty template (matches the game's struct flags)
		WithNoDestructor = true,
		WithPlainOldData = true, // pointer copy is the right copy; the GC sees the node through AddStructReferencedObjects
	};
};

static void MaterialInstanceTrailingVariants(UObject* Object, FArchive& Ar, int64 ExportEndOffset)
{
	if (!Ar.IsLoading() || !Ar.IsPersistent() || !Object->GetPackage()->bIsCookedForEditor)
	{
		return;
	}
	if (Ar.Tell() + int64(sizeof(int32)) > ExportEndOffset)
	{
		return; // nothing left in the export
	}
	int32 Num = 0;
	Ar << Num;
	if (Num < 0 || Num > 100000)
	{
		UE_LOG(LogDbdModkitGame, Warning, TEXT("%s: implausible trailing variant count %d, skipping to the end of the export"), *Object->GetPathName(), Num);
		Ar.Seek(ExportEndOffset);
		return;
	}
	for (int32 Index = 0; Index < Num && !Ar.IsError() && Ar.Tell() < ExportEndOffset; ++Index)
	{
		FDbdVariantConfigurator Discarded;
		Discarded.Serialize(Ar);
	}
}

// Thunks of functions the game's KismetMathLibrary and KismetSystemLibrary have and the editor's stock classes lack (or have with
// other parameter types). Parameters are read in the game's order and types (jmap), the results written in the game's types.
namespace DbdEngineThunks
{
/** The stock native functions of the replaced signatures, saved before the generator replaces them (Register). */
FNativeFuncPtr GStockMultiplyMultiplyFloat = nullptr;
FNativeFuncPtr GStockPrintString = nullptr;
FNativeFuncPtr GStockPrintText = nullptr;

/** True when the calling script is from a cooked package: only those use the game's signature. Editor and engine scripts use the stock one. */
bool IsCookedCaller(const FFrame& Stack)
{
	const UObject* Caller = Stack.Node;
	const UPackage* Pkg = Caller ? Caller->GetOutermost() : nullptr;
	return Pkg && (Pkg->HasAnyPackageFlags(PKG_Cooked | PKG_FilterEditorOnly) || Pkg->bIsCookedForEditor);
}

/** Runs the stock function for a non-cooked caller. */
void CallStock(FNativeFuncPtr Stock, UObject* Context, FFrame& Stack, void* const Result)
{
	if (Stock)
	{
		Stock(Context, Stack, Result);
	}
}

#define DBD_FLOAT_BINARY(Name, Expr)                                              \
	void Name(UObject* Context, FFrame& Stack, RESULT_DECL)                       \
	{                                                                             \
		P_GET_PROPERTY(FFloatProperty, A);                                        \
		P_GET_PROPERTY(FFloatProperty, B);                                        \
		P_FINISH;                                                                 \
		P_NATIVE_BEGIN;                                                           \
		*(float*)RESULT_PARAM = (Expr);                                           \
		P_NATIVE_END;                                                             \
	}
#define DBD_FLOAT_COMPARE(Name, Op)                                               \
	void Name(UObject* Context, FFrame& Stack, RESULT_DECL)                       \
	{                                                                             \
		P_GET_PROPERTY(FFloatProperty, A);                                        \
		P_GET_PROPERTY(FFloatProperty, B);                                        \
		P_FINISH;                                                                 \
		P_NATIVE_BEGIN;                                                           \
		*(bool*)RESULT_PARAM = (A Op B);                                          \
		P_NATIVE_END;                                                             \
	}

	DBD_FLOAT_BINARY(Add_FloatFloat, A + B)
	DBD_FLOAT_BINARY(Subtract_FloatFloat, A - B)
	DBD_FLOAT_BINARY(Multiply_FloatFloat, A * B)
	// stock Divide_DoubleDouble returns 0 for a zero divisor (and reports it to the Blueprint runtime, which is not reproduced here)
	DBD_FLOAT_BINARY(Divide_FloatFloat, B == 0.0f ? 0.0f : A / B)
	DBD_FLOAT_COMPARE(Less_FloatFloat, <)
	DBD_FLOAT_COMPARE(Greater_FloatFloat, >)
	DBD_FLOAT_COMPARE(LessEqual_FloatFloat, <=)
	DBD_FLOAT_COMPARE(GreaterEqual_FloatFloat, >=)
	DBD_FLOAT_COMPARE(EqualEqual_FloatFloat, ==)
	DBD_FLOAT_COMPARE(NotEqual_FloatFloat, !=)

#undef DBD_FLOAT_BINARY
#undef DBD_FLOAT_COMPARE

	void MultiplyMultiply_DoubleDouble(UObject* Context, FFrame& Stack, RESULT_DECL)
	{
		P_GET_PROPERTY(FDoubleProperty, Base);
		P_GET_PROPERTY(FDoubleProperty, Exp);
		P_FINISH;
		P_NATIVE_BEGIN;
		*(double*)RESULT_PARAM = FMath::Pow(Base, Exp);
		P_NATIVE_END;
	}

	void NearlyEqual_DoubleDouble(UObject* Context, FFrame& Stack, RESULT_DECL)
	{
		P_GET_PROPERTY(FDoubleProperty, A);
		P_GET_PROPERTY(FDoubleProperty, B);
		P_GET_PROPERTY(FDoubleProperty, ErrorTolerance);
		P_FINISH;
		P_NATIVE_BEGIN;
		*(bool*)RESULT_PARAM = FMath::IsNearlyEqual(A, B, ErrorTolerance);
		P_NATIVE_END;
	}

	// the editor's stock UKismetMathLibrary::MultiplyMultiply_FloatFloat takes doubles; the game's takes floats
	void MultiplyMultiply_FloatFloat(UObject* Context, FFrame& Stack, RESULT_DECL)
	{
		if (!IsCookedCaller(Stack))
		{
			CallStock(GStockMultiplyMultiplyFloat, Context, Stack, RESULT_PARAM);
			return;
		}
		P_GET_PROPERTY(FFloatProperty, Base);
		P_GET_PROPERTY(FFloatProperty, Exp);
		P_FINISH;
		P_NATIVE_BEGIN;
		*(float*)RESULT_PARAM = (float)FMath::Pow((double)Base, (double)Exp);
		P_NATIVE_END;
	}

	/** The game's Key is an int32; the stock parameter is an FName. 0 and -1 mean no key. */
	FName KeyName(int32 Key)
	{
		return (Key == 0 || Key == -1) ? NAME_None : FName(*FString::FromInt(Key));
	}

	void PrintString(UObject* Context, FFrame& Stack, RESULT_DECL)
	{
		if (!IsCookedCaller(Stack))
		{
			CallStock(GStockPrintString, Context, Stack, RESULT_PARAM);
			return;
		}
		P_GET_OBJECT(UObject, WorldContextObject);
		P_GET_PROPERTY(FStrProperty, InString);
		P_GET_UBOOL(bPrintToScreen);
		P_GET_UBOOL(bPrintToLog);
		P_GET_STRUCT(FLinearColor, TextColor);
		P_GET_PROPERTY(FFloatProperty, Duration);
		P_GET_PROPERTY(FIntProperty, Key);
		P_FINISH;
		P_NATIVE_BEGIN;
		UKismetSystemLibrary::PrintString(WorldContextObject, InString, bPrintToScreen, bPrintToLog, TextColor, Duration, KeyName(Key));
		P_NATIVE_END;
	}

	void PrintText(UObject* Context, FFrame& Stack, RESULT_DECL)
	{
		if (!IsCookedCaller(Stack))
		{
			CallStock(GStockPrintText, Context, Stack, RESULT_PARAM);
			return;
		}
		P_GET_OBJECT(UObject, WorldContextObject);
		P_GET_PROPERTY(FTextProperty, InText);
		P_GET_UBOOL(bPrintToScreen);
		P_GET_UBOOL(bPrintToLog);
		P_GET_STRUCT(FLinearColor, TextColor);
		P_GET_PROPERTY(FFloatProperty, Duration);
		P_GET_PROPERTY(FIntProperty, Key);
		P_FINISH;
		P_NATIVE_BEGIN;
		UKismetSystemLibrary::PrintText(WorldContextObject, InText, bPrintToScreen, bPrintToLog, TextColor, Duration, KeyName(Key));
		P_NATIVE_END;
	}
}

class FDbdSuzieExtension : public ISuzieGameExtension
{
public:
	virtual FName GetProfileId() const override { return FName(TEXT("dbd")); }
	virtual void Register(FSzExtensionRegistry& Registry) override
	{
		Registry.AddStructOps<FDbdVariantConfigurator>(FName(TEXT("dbd.variant_configurator")));
		Registry.AddStructOps<FDbdBarkNodeTemplate>(FName(TEXT("dbd.bark_node_template")));
		Registry.AddPostSerialize(FName(TEXT("dbd.material_instance_trailing_variants")), &MaterialInstanceTrailingVariants);

		// Register runs before the generator binds the thunks, so the stock functions still hold their own native pointers
		auto StockOf = [](const TCHAR* Path) -> FNativeFuncPtr
		{
			UFunction* F = FindObject<UFunction>(nullptr, Path);
			return F ? F->GetNativeFunc() : nullptr;
		};
		DbdEngineThunks::GStockMultiplyMultiplyFloat = StockOf(TEXT("/Script/Engine.KismetMathLibrary:MultiplyMultiply_FloatFloat"));
		DbdEngineThunks::GStockPrintString = StockOf(TEXT("/Script/Engine.KismetSystemLibrary:PrintString"));
		DbdEngineThunks::GStockPrintText = StockOf(TEXT("/Script/Engine.KismetSystemLibrary:PrintText"));

		const TCHAR* KML = TEXT("/Script/Engine.KismetMathLibrary:");
		Registry.AddNativeFunction(FString(KML) + TEXT("Add_FloatFloat"), &DbdEngineThunks::Add_FloatFloat);
		Registry.AddNativeFunction(FString(KML) + TEXT("Subtract_FloatFloat"), &DbdEngineThunks::Subtract_FloatFloat);
		Registry.AddNativeFunction(FString(KML) + TEXT("Multiply_FloatFloat"), &DbdEngineThunks::Multiply_FloatFloat);
		Registry.AddNativeFunction(FString(KML) + TEXT("Divide_FloatFloat"), &DbdEngineThunks::Divide_FloatFloat);
		Registry.AddNativeFunction(FString(KML) + TEXT("Less_FloatFloat"), &DbdEngineThunks::Less_FloatFloat);
		Registry.AddNativeFunction(FString(KML) + TEXT("Greater_FloatFloat"), &DbdEngineThunks::Greater_FloatFloat);
		Registry.AddNativeFunction(FString(KML) + TEXT("LessEqual_FloatFloat"), &DbdEngineThunks::LessEqual_FloatFloat);
		Registry.AddNativeFunction(FString(KML) + TEXT("GreaterEqual_FloatFloat"), &DbdEngineThunks::GreaterEqual_FloatFloat);
		Registry.AddNativeFunction(FString(KML) + TEXT("EqualEqual_FloatFloat"), &DbdEngineThunks::EqualEqual_FloatFloat);
		Registry.AddNativeFunction(FString(KML) + TEXT("NotEqual_FloatFloat"), &DbdEngineThunks::NotEqual_FloatFloat);
		Registry.AddNativeFunction(FString(KML) + TEXT("MultiplyMultiply_DoubleDouble"), &DbdEngineThunks::MultiplyMultiply_DoubleDouble);
		Registry.AddNativeFunction(FString(KML) + TEXT("NearlyEqual_DoubleDouble"), &DbdEngineThunks::NearlyEqual_DoubleDouble);
		Registry.AddNativeFunction(FString(KML) + TEXT("MultiplyMultiply_FloatFloat"), &DbdEngineThunks::MultiplyMultiply_FloatFloat);
		Registry.AddNativeFunction(TEXT("/Script/Engine.KismetSystemLibrary:PrintString"), &DbdEngineThunks::PrintString);
		Registry.AddNativeFunction(TEXT("/Script/Engine.KismetSystemLibrary:PrintText"), &DbdEngineThunks::PrintText);
	}
};

class FDbdModkitGameModule : public IModuleInterface
{
public:
	virtual void StartupModule() override
	{
		IModularFeatures::Get().RegisterModularFeature(ISuzieGameExtension::GetModularFeatureName(), &Extension);
	}
	virtual void ShutdownModule() override
	{
		IModularFeatures::Get().UnregisterModularFeature(ISuzieGameExtension::GetModularFeatureName(), &Extension);
	}

private:
	FDbdSuzieExtension Extension;
};

IMPLEMENT_MODULE(FDbdModkitGameModule, DBDModkitGame)
