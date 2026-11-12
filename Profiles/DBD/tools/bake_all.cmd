@echo off
rem Regenerates every data file from the jmap. Needs python 3 (+ cityhash only for roots_from_logs.py).
cd /d %~dp0..
python -I tools\extract_fork_additions.py
python -I tools\scan_stock.py
python -I tools\roots_from_logs.py
python -I tools\dbd_native_baker.py --cdo-out data\dbd_native_cdo.json --validate
python -I tools\dbd_native_baker.py --roots @data\roots_17_failing.txt --no-diff --out data\closure_17assets_hard.json
python -I tools\dbd_native_baker.py --roots @data\roots_17_failing.txt --no-interfaces --no-diff --out data\closure_17assets_hard_nointf.json
python -I tools\dbd_native_baker.py --roots @data\roots_17_failing.txt --all-refs --no-diff --out data\closure_17assets_allrefs.json
python -I tools\dbd_native_baker.py --roots CorePlayerCardAnimationWidget,DBDImage --no-interfaces --no-diff --out data\m1_WBP_JE_BNR_07.json --pretty
rem Import scan (needs the game drive; key path is an argument and is never printed):
rem   dotnet build tools\ImportScan -c Release -o <outdir>
rem   dotnet <outdir>\ImportScan.dll "E:\Dead by Daylight\DeadByDaylight\Content\Paks" <keyfile> data\bp_native_deps.csv
rem   python -I tools\scan_summary.py
