import argparse,subprocess
from pathlib import Path
from isolated_native import isolated_source_root
p=argparse.ArgumentParser();p.add_argument('--source-root',type=Path,default=Path(__file__).resolve().parents[3]);p.add_argument('--derived-data',type=Path,required=True);p.add_argument('--baseline');args=p.parse_args()
r=isolated_source_root(args.source_root);base=r/'packages/ChatUI/Sources/ChatUI';paths=[base/'ChatController.swift',base/'ChatInteractiveContentView.swift'];saved={x:x.read_bytes() for x in paths};helper=base/'SpoilerMediaHarness.swift';assert not helper.exists()
try:
 if args.baseline:paths[1].write_bytes(subprocess.check_output(['git','show',args.baseline+':'+str(paths[1].relative_to(r))],cwd=r))
 helper.write_bytes(Path(__file__).with_name('SpoilerMediaHarness.swift').read_bytes())
 x=paths[0];s=x.read_text();marker='    public override func viewDidAppear(_ animated: Bool) {\n        super.viewDidAppear(animated)';assert s.count(marker)==1;x.write_text(s.replace(marker,marker+'\n        codexInstallSpoilerEvidence(source: chatInteraction, parent: genericView)'))
 x=paths[1];s=x.read_text();marker='    private var previousIsSpoiler: Bool? = nil';assert s.count(marker)==1;x.write_text(s.replace(marker,'    func codexSpoilerProbe() -> (CGImage?, Bool) { (image.view?.image ?? image.layer?.image, inkView != nil) }\n'+marker))
 result=subprocess.run(['xcodebuild','-workspace','Telegram-Mac.xcworkspace','-scheme','Telegram','-configuration','Debug','-destination','platform=macOS,arch=arm64','-derivedDataPath',str(args.derived_data.resolve()),'-jobs','1','CODE_SIGNING_ALLOWED=NO','COMPILER_INDEX_STORE_ENABLE=NO','build'],cwd=r)
finally:
 for x,data in saved.items():x.write_bytes(data)
 helper.unlink(missing_ok=True)
raise SystemExit(result.returncode)
