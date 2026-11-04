import argparse,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('--revision');args=p.parse_args()
def source(name):
 path='packages/ChatListUI/Sources/ChatListUI/'+name+'.swift'
 if args.revision:
  value=subprocess.run(['git','show',args.revision+':'+path],cwd=root,capture_output=True,text=True)
  return value.stdout if value.returncode==0 else ''
 return (root/path).read_text()
s=source('SearchPeerReadMenuItem')
helper='\n'.join(line for line in s.splitlines() if not line.startswith('import ')) if s else 'func searchPeerReadMenuItem(context:any AccountContextProtocol,peerId:PeerId)->Signal<ContextMenuItem?,NoError> { .single(nil) }'
if 'target: SearchControllerTarget' not in helper:
 helper+='\nfunc searchPeerReadMenuItem(context:any AccountContextProtocol,peerId:PeerId,target:SearchControllerTarget)->Signal<ContextMenuItem?,NoError> { searchPeerReadMenuItem(context:context,peerId:peerId) }'
s=source('PopularPeersRowItem');marker='override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {';start=s.index(marker)+len(marker);end=start;depth=1
while depth:
 depth+=(s[end]=='{')-(s[end]=='}');end+=1
fixture=Path(__file__).with_name('Checks.swift').read_text().replace('__HELPER__',helper).replace('__POPULAR_BODY__',s[start:end-1])
harness=Path(__file__).with_name('SearchUnreadHarness.swift').read_text()
lease=harness[harness.index('private enum SearchReadRunLease'):harness.index('private final class SearchReadButton')]
fixture=fixture.replace('__LEASE__',lease)
if not args.revision:
 assert 'searchPeerReadMenuItem(context: arguments.context, peerId: peerId, target: arguments.target)' in source('SearchController')

with tempfile.TemporaryDirectory() as t:
 t=Path(t);(t/'main.swift').write_text(fixture)
 subprocess.run(['swiftc',str(t/'main.swift'),'-o',str(t/'checks')],check=True)
 raise SystemExit(subprocess.run([str(t/'checks')]).returncode)
