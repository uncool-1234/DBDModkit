# jmap and minidump (user supplied)

Agents and scripts of this project never produce these files and never run the game. Producing them requires running the game (or a memory dump of it), with whatever anti-cheat and terms-of-service consequences that has. It is the user's own decision and responsibility, done with the user's own install.

## What they are

- `.jmap`: JSON reflection dump (classes, structs, enums, properties, default object values, vtables) of the running game process, in the format of trumank/jmap's `jmap_dumper`. Jmaps of a game version circulate in the modding community like the AES key; none ships with the modkit. Suzie reads it at every editor start ([native-type-generation.md](native-type-generation.md)).
- `.DMP`: full-memory Windows minidump of the running game process. `oatmealf-5.7` reads the game's uniform buffer layouts from it ([game-update.md](game-update.md)). It is produced under the same conditions as the jmap.

## Where the files go

Keep the files (jmap, key file, game minidump) in a folder no repository tracks, for example `DeadByDaylight-Data` in the layout root, which git ignores. In a project the jmap sits in `<Project>\ModkitData`; the setup window records its path as `Jmap=` in `<Project>\ModkitData\ModkitLocal.ini`, and `-SuzieJmap=<file>` overrides it. Nothing else records its path.

## Who needs them

- Every user needs the jmap of the game version they run: the editor generates no types without it (`Suzie idle: profile '<id>' needs the game's jmap, ...`). The profile holds no type data. Data in it that derives from the game: `uniform_layouts.txt` (layouts read from a game minidump) and the cipher steps in `engine.ini`; the test references (`data/golden`: names and layouts of the game's types; `sweeps/`: asset paths) are local files that git does not track.
- The minidump is a developer input for new uniform buffer layouts ([game-update.md](game-update.md)); ordinary users do not need it.
- A new game needs its own jmap, a new profile folder created from the DBD profile, its own `uniform_layouts.txt` when uniform buffer layouts differ ([game-update.md](game-update.md)), and its own engine branch when engine struct sizes differ ([engine-fork.md](engine-fork.md)).
