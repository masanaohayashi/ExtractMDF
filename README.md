# ExtractMDF

English follow Japanese

X68000の **LZMで圧縮されたMDFファイル** を解凍する、Swift / SwiftUI製のMacアプリです。解凍処理もSwiftで実装しており、エミュレータや外部コマンドは不要です。

## 起動

ビルド済みアプリは `build/ExtractMDF.app`。Finderから開けます。

```sh
./scripts/build-app.sh
open build/ExtractMDF.app
```

macOS 13以降、Swift 5.9以降が必要です。このMacで作成したアプリはApple Silicon用で、ローカル実行用のアドホック署名を付けています。配布用のDeveloper ID署名・公証は行っていません。

Xcodeで `Package.swift` を開き、ExtractMDFを実行することもできます。

配布用のUniversal（Apple Silicon / Intel）ビルドは次のコマンドで作成します。Developer ID証明書とキーチェーンの公証プロファイルが必要です。署名・公証・チケット添付とGatekeeper検証を行い、`build/release/<バージョン>/` にZIPとSHA-256チェックサムを出力します。

```sh
./scripts/release-macos.sh
```

既定の公証プロファイルは `Notalization2021` です。`SIGNING_IDENTITY` と `NOTARY_PROFILE` 環境変数で変更できます。

## 表示言語

日本語・英語に対応しています。macOSの優先する言語に従って表示します。アプリ単位で変更する場合は、システム設定の「一般 → 言語と地域 → アプリケーション」でExtractMDFの言語を指定し、アプリを再起動してください。日本語以外の未対応言語では英語を使用します。

## 使い方

1. MDFファイルをウインドウにドロップ、または「ファイルを選択…」で追加します。フォルダを追加すると、サブフォルダ内のMDFも検索します。
2. 格納ファイル名・種類・サイズを確認します。取り出さないファイルはチェックを外せます。
3. 保存先フォルダを選ぶか、「元のMDFと同じフォルダに保存」にチェックを入れ、「ファイルを解凍」を押します。複数フォルダのMDFを追加した場合は、それぞれのMDFがあるフォルダに保存します。
4. フォルダボタンから保存結果をFinderに表示できます。

元のMDFは変更しません。保存先を指定した場合は、そのフォルダに直接解凍します。

同名ファイルがある場合は「上書き」「スキップ」「キャンセル」を選びます。「すべてに適用」にチェックすると、その解凍処理中の残りの同名ファイルにも同じ選択を適用します。キャンセルすると以降の処理を止めます。保存済みのファイルは残ります。

開始前に保存先への書き込みを確認します。書き込みできない場合はOKアラートを表示し、処理全体を終了します。処理途中に書き込み権限エラーが発生した場合も終了します。破損した格納データはエラーを表示し、ほかのファイルの処理を続けます。

CLIでは同名ファイルに番号を付けて保存します。

## 対応形式

- LZMの `MDF0\r\n` 形式
- 格納された曲データ（RCP/MCP/MID等）、音色（CM6等）、歌詞（WRD）の復元
- Shift JISの曲名・格納ファイル名
- LZEXE系の短距離・長距離・重複参照と可変長コピー

MIDIへの形式変換や再生は行いません。RCPはRCP、CM6はCM6として元のバイト列に復元します。一般のディスクイメージMDF、LZMA/SlaxのLZM、LZZのZDF、LZX圧縮MDXは対象外です。

入力は256 MiB、展開後は1ファイル256 MiB・1アーカイブ合計512 MiBまで。サイズ、参照範囲、終端コードを検証します。MDF0には本ツールが検証可能なチェックサムがないため、サイズを保つすべての破損を検出できるわけではありません。

## コマンドライン

```sh
swift run lzmtool input.mdf             # 中身を一覧表示
swift run lzmtool input.mdf output      # 全ファイルをoutputに解凍
swift test
```

## 構成

- `Sources/LZMCore`: MDF0解析、展開、安全な保存
- `Sources/ExtractMDF`: SwiftUI GUI
- `Sources/lzmtool`: 検証にも使えるCLI
- `Tests/LZMCoreTests`: 元のLZMが生成した自作MIDIのテスト素材、破損・上書き防止テスト
- `docs/FORMAT.md`: 形式の調査記録
- `docs/VALIDATION.md`: 実データの比較結果

## 調査資料

LZM v2.91（HARPOON, 1990–1991）のマニュアルおよび展開ルーチンを確認し、Swiftで実装しました。元のLZM本体やエミュレータはアプリに含めていません。

- [RC v2.91の配布アーカイブ](https://nfggames.com/X68000/Mirrors/x68pub/x68tools/SOUND/_MIDI/RC/RC291.LZH): RC.DOCとLZM.X
- [STed2の当時のドキュメント](https://github.com/cat2151/STed2.07m/blob/master/STED207/STED2.DOC): LZM/LZZとの関係
- [LZZの種別定義](https://github.com/kg68k/zmusic2/blob/main/src/include/LzzConst.mac)
- [month & msch作者の対応形式一覧](https://bitarts.co.jp/software/tma.html)

テストの参照実行には [run68x](https://github.com/kg68k/run68x) を使用しました。ユーザー提供の音楽ファイルやその解凍結果はリポジトリに含めていません。

## ライセンス

MITライセンスです。詳細は [LICENSE](LICENSE) を参照してください。原版LZMや参照先のソフトウェアは含まず、それらのライセンスを変更するものではありません。

---

# English

ExtractMDF is a Mac application written in Swift and SwiftUI that extracts **MDF archives compressed with LZM for the X68000**. The decoder is implemented in Swift; no emulator or external command is required.

## Build and launch

Build the application and open it in Finder or run:

```sh
./scripts/build-app.sh
open build/ExtractMDF.app
```

Requires macOS 13 or later and Swift 5.9 or later to build. The app built on this machine targets Apple Silicon and uses an ad hoc signature for local use. It is not Developer ID signed or notarized for distribution.

You can also open `Package.swift` in Xcode and run the ExtractMDF target.

To create a Universal release for Apple Silicon and Intel Macs, run the following command with a Developer ID certificate and a Keychain notarization profile available:

```sh
./scripts/release-macos.sh
```

The script signs, notarizes, staples, and checks the app with Gatekeeper. It writes the ZIP and SHA-256 checksum to `build/release/<version>/`. The default notarization profile is `Notalization2021`; override it with `NOTARY_PROFILE`, and use `SIGNING_IDENTITY` to select another certificate.

## Language

The interface supports Japanese and English and follows the preferred languages in macOS. To choose a language for ExtractMDF, use System Settings → General → Language & Region → Applications, then restart the app. English is the fallback for unsupported languages.

## Usage

1. Drop MDF files onto the window or click **Choose Files…**. Adding a folder also searches its subfolders for MDF files.
2. Review the archived filenames, types, and sizes. Uncheck files you do not want to extract.
3. Choose a destination folder, or check **Save in the same folder as each MDF file**, then click **Extract**. With the checkbox enabled, archives from different folders are each extracted beside their source MDF.
4. Use the folder button to reveal extracted files in Finder.

Original MDF files are kept. When you choose a destination folder, files are extracted directly into that folder.

If a filename already exists, choose **Overwrite**, **Skip**, or **Cancel**. Check **Apply to All** to use the same choice for the remaining filename conflicts in the current extraction. Cancel stops further extraction; files already saved remain in place.

Before extraction, the app checks whether it can write to every destination folder. If a folder is not writable, an alert with an **OK** button appears and the entire operation stops. A write permission error during extraction also stops the operation. Damaged archive entries are reported as errors, and processing continues with the other files.

The CLI adds a number to duplicate filenames instead of prompting.

## Supported format

- LZM archives with the `MDF0\r\n` signature
- Restoration of archived song data (RCP/MCP/MID and others), tone data (such as CM6), and lyrics (WRD)
- Shift JIS archive titles and filenames
- LZEXE-style short, long, overlapping, and variable-length copies

The app does not play files or convert them to MIDI. RCP files remain RCP, CM6 files remain CM6, and their original bytes are restored. MDF disk images, LZMA/Slax LZM files, LZZ ZDF archives, and LZX-compressed MDX files are not supported.

Limits are 256 MiB per input archive, 256 MiB per extracted file, and 512 MiB of extracted data per archive. Sizes, reference bounds, and end markers are validated. MDF0 has no checksum that this tool can validate, so not every corruption that preserves the expected size can be detected.

## Command line

```sh
swift run lzmtool input.mdf             # List archive contents
swift run lzmtool input.mdf output      # Extract all files into output
swift test
```

## Project layout

- `Sources/LZMCore`: MDF0 parsing, decompression, and safe file saving
- `Sources/ExtractMDF`: SwiftUI interface
- `Sources/lzmtool`: CLI, also used for validation
- `Tests/LZMCoreTests`: Original-LZM-generated fixtures from self-created MIDI data, plus decoder, file saving, permission, and localization tests
- `docs/FORMAT.md`: Format investigation notes (Japanese)
- `docs/VALIDATION.md`: Comparisons against real archive data (Japanese)

## References

The Swift implementation was developed by examining the manual and decompression routine of LZM v2.91 (HARPOON, 1990–1991). Neither the original LZM executable nor an emulator is bundled with the app.

- [RC v2.91 distribution archive](https://nfggames.com/X68000/Mirrors/x68pub/x68tools/SOUND/_MIDI/RC/RC291.LZH): contains RC.DOC and LZM.X
- [Historical STed2 documentation](https://github.com/cat2151/STed2.07m/blob/master/STED207/STED2.DOC): relationship to LZM/LZZ
- [LZZ type definitions](https://github.com/kg68k/zmusic2/blob/main/src/include/LzzConst.mac)
- [Supported formats listed by the author of month & msch](https://bitarts.co.jp/software/tma.html)

[run68x](https://github.com/kg68k/run68x) was used to run the original decoder for reference comparisons. User-provided music files and their extracted contents are not included in the repository.

## License

Licensed under the MIT License. See [LICENSE](LICENSE). The original LZM and referenced software are not included; this license does not change their respective licenses.
