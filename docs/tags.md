# Gameplay tags

Cooked content references gameplay tags that the game registers through `GameplayTagsSettings`. The stock editor warns `Invalid GameplayTag` for every tag it does not know.

- Source: the object `/Script/GameplayTags.Default__GameplayTagsSettings` of the game's jmap, properties `GameplayTagList` and `GameplayTagRedirects`.
- Automatic: after generation Suzie writes the tag list to `<Project>\<tags_ini>` (DBD: `Config/Tags/DBDGameTags.ini`; `[/Script/GameplayTags.GameplayTagsList]` with plain repeated `GameplayTagList=(Tag="X",DevComment="")` keys, because a `+` prefix yields no entries in `Config/Tags` files) and the redirects to `<Project>\Config\DefaultGameplayTags.ini` (`ImportTagsFromConfig=True`, `WarnOnInvalidTags=True`, one `+GameplayTagRedirects=(OldTagName=...,NewTagName=...)` per redirect). A file is written only when its content differs; then the tag tree is refreshed and `Gameplay tags written from the jmap: N tags, M redirects` is logged. Changed redirects apply from the next editor start.
- `Profiles/<Game>/tags/tags.json` holds `tags_ini` and `probe_tag`.
- The stock `GameplayTagsManager` reads `Config/Tags/*.ini` of the project.
- `Suzie.TagInfo [tag...|refresh]` prints the manager's tag count and whether the probe tag (`State.GuidedAction.BeingWokenUp`) is valid; `refresh` runs `EditorRefreshGameplayTagTree` and prints the tag count.
- The tag count of the manager exceeds the ini tag count because the stock engine and plugins register tags too.
