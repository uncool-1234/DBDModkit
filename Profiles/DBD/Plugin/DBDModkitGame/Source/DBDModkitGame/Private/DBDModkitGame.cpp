// DBD profile extension for Suzie. All DBD specific code of the profile lives here (everything else is data):
//  1. dbd.variant_configurator: the game serializes its variant configurator struct RAW (no property header): object reference, FString, tag.
//  2. dbd.material_instance_trailing_variants: after the reflected part of every cooked MaterialInstance export the game appends a count and
//     that many raw variant configurators.
//  3. dbd.bark_node_template: BhvrBarkNodeTemplate (16 bytes in memory, no reflected members) is a hand serialized inline object:
//     int32 bHasNode; if set: class package index, then that class instance's own unversioned property data inline, with NO serial size.
//     Because there is no size it cannot be skipped, it has to be decoded: a transient instance is created and read with
//     UObject::SerializeScriptProperties (format: CUE4Parse FBhvrBarkNodeTemplate.cs, verified on BarkRuleDB bytes).
// All are bound to types/classes by data: load/native_ops.json and load/skip.json of the profile.
#include "SuzieExtension.h"

#include "GameplayTagContainer.h"
#include "Modules/ModuleManager.h"
#include "Serialization/Archive.h"
#include "UObject/Package.h"
#include "UObject/GarbageCollection.h"
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

class FDbdSuzieExtension : public ISuzieGameExtension
{
public:
	virtual FName GetProfileId() const override { return FName(TEXT("dbd")); }
	virtual void Register(FSzExtensionRegistry& Registry) override
	{
		Registry.AddStructOps<FDbdVariantConfigurator>(FName(TEXT("dbd.variant_configurator")));
		Registry.AddStructOps<FDbdBarkNodeTemplate>(FName(TEXT("dbd.bark_node_template")));
		Registry.AddPostSerialize(FName(TEXT("dbd.material_instance_trailing_variants")), &MaterialInstanceTrailingVariants);
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
