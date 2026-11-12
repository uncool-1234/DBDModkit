@echo off
rem Regenerates the data files of the profile from the game's jmap (python 3 only).
rem Inputs (machine local, see ModkitLocal.example.ini): SUZIE_JMAP (jmap), data\editor_schemas_stock.tsv (reflection of the STOCK editor), data\stock_info.json.
rem   data\editor_schemas_stock.tsv comes from a stock editor's schema dump, or from a dump taken on a modified fork with:
rem     python -I tools\make_stock_editor_schema.py --repo <engine repo> --commit <commit that added members> --in <dump.tsv> --out data\editor_schemas_stock.tsv --marks-out schema\_fork_additions.json
cd /d %~dp0..
if "%SUZIE_JMAP%"=="" (echo set SUZIE_JMAP to the game's jmap & exit /b 1)
rem whole game: types, CDO deltas, and schema\engine_diff.json (recipes for every engine type whose members differ)
python -I tools\dbd_native_baker.py --editor-schemas data\editor_schemas_stock.tsv --out data\bake\types.json --cdo-out data\bake\cdo.json
rem the usmap cross-check (optional): add --validate with SUZIE_USMAP set
rem gameplay tags (reads the jmap's tag settings CDO; writes into the project given by --project)
rem   python -I ..\..\Tools\suzie_tags.py --jmap %SUZIE_JMAP% --project <project dir>
