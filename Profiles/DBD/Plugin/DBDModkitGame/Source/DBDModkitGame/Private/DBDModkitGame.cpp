// DBD profile extension for Suzie. All DBD specific code of the profile lives here (everything else is data):
//  1. dbd.variant_configurator: the game serializes its variant configurator struct RAW (no property header): object reference, FString, tag.
//  2. dbd.material_instance_trailing_variants: after the reflected part of every cooked MaterialInstance export the game appends a count and
//     that many raw variant configurators.
// Both are bound to types/classes by data: load/native_ops.json and load/skip.json of the profile.
#include "SuzieExtension.h"

#include "GameplayTagContainer.h"
#include "Modules/ModuleManager.h"
#include "Serialization/Archive.h"
#include "UObject/Package.h"

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
