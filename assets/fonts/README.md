# Packaged UI fonts

The runtime font chain is Baloo 2 for Latin and numbers, followed by three
weight-matched Resource Han Rounded CN subsets for Chinese.

Resource Han Rounded CN comes from the upstream `v1.910` CFF2 CN release:

- <https://github.com/CyanoHao/Resource-Han-Rounded/releases/tag/v1.910>
- archive SHA-256: `4ad7b141535a1f11831287b0a6f71ddcec8daa92dc1d82c59892068f8ae5df09`
- extracted `ResourceHanRoundedCN-VF.otf` SHA-256: `ee3f276c9f9ee77c726d4e9c88350a3de73fb297633c54d510971ee636dceb1e`
- license: SIL Open Font License 1.1 (`OFL-ResourceHanRounded.txt`)

The full masters are intentionally not shipped with the game. To rebuild after
localization changes, extract `ResourceHanRoundedCN-VF.otf` from the official
`RHR-CFF2-CN-1.910.7z` archive, then run:

```sh
python3 -m pip install fonttools
python3 tools/subset_fonts.py --source /path/to/ResourceHanRoundedCN-VF.otf
```

The script verifies the audited upstream hash, subsets the variable master,
pins Medium/Bold/Heavy at full rounding, downgrades CFF2 to static CFF OTF, and
produces deterministic runtime fonts containing every character in
`localization/ui.csv`, printable ASCII, formatted-value punctuation, and the
complete 3,755-character GB2312 level-1 common-Han buffer.
