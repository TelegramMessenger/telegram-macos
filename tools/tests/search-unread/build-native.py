import argparse,subprocess
from pathlib import Path
from isolated_native import isolated_source_root
p=argparse.ArgumentParser();p.add_argument('--source-root',type=Path,default=Path(__file__).resolve().parents[3]);p.add_argument('--derived-data',type=Path,required=True);p.add_argument('--baseline');args=p.parse_args()
r=isolated_source_root(args.source_root);base=r/'packages/ChatListUI/Sources/ChatListUI';paths=[base/x for x in ['SearchController.swift','PopularPeersRowItem.swift','PeersListController.swift']];saved={x:x.read_bytes() for x in paths};helper=base/'SearchUnreadHarness.swift';assert not helper.exists()
try:
 if args.baseline:
  for x in paths[:2]:x.write_bytes(subprocess.check_output(['git','show',args.baseline+':'+str(x.relative_to(r))],cwd=r))
 helper.write_bytes(Path(__file__).with_name('SearchUnreadHarness.swift').read_bytes())
 x=paths[0];x.write_text(x.read_text().replace('private func peerContextMenuItems(', 'func peerContextMenuItems(',1))
 x=paths[1];x.write_text(x.read_text().replace('private final class PopularPeerItem :','final class PopularPeerItem :',1))
 x=paths[2];s=x.read_text();marker='    open override func viewDidAppear(_ animated: Bool) {\n        super.viewDidAppear(animated)';assert s.count(marker)==1;x.write_text(s.replace(marker,marker+'\n        codexInstallSearchReadEvidence(context: context, parent: genericView)'))
 result=subprocess.run(['xcodebuild','-workspace','Telegram-Mac.xcworkspace','-scheme','Telegram','-configuration','Debug','-destination','platform=macOS,arch=arm64','-derivedDataPath',str(args.derived_data.resolve()),'-jobs','1','CODE_SIGNING_ALLOWED=NO','COMPILER_INDEX_STORE_ENABLE=NO','build'],cwd=r)
finally:
 for x,data in saved.items():x.write_bytes(data)
 helper.unlink(missing_ok=True)
raise SystemExit(result.returncode)
