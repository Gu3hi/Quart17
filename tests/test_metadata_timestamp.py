"""Run the production timestamp parser with Foundation on the build Mac."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "QPlayerView.m").read_text(encoding="utf-8")
parser = re.search(r"static NSTimeInterval QMetadataTimestamp\(id value\) \{.*?\n\}", source, re.S)
assert parser
assert 'QMetadataTimestamp(info[QKey(QTimestampKey,' in source
with tempfile.TemporaryDirectory(prefix="quart-timestamp-") as directory:
    test = Path(directory) / "test.m"
    test.write_text('''#import <Foundation/Foundation.h>
#include <assert.h>
''' + parser[0] + '''
int main(void) { @autoreleasepool {
    assert(QMetadataTimestamp([NSDate dateWithTimeIntervalSince1970:1792950854]) == 1792950854);
    assert(QMetadataTimestamp(@1792950854) == 1792950854);
    assert(QMetadataTimestamp(nil) == 0);
    assert(QMetadataTimestamp(NSNull.null) == 0);
    assert(QMetadataTimestamp(@"invalid") == 0);
} return 0; }
''', encoding="utf-8")
    binary = str(Path(directory) / "test")
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-framework", "Foundation", str(test), "-o", binary], check=True)
    subprocess.run([binary], check=True)
print("PASS: production timestamp parser accepts NSDate/NSNumber and rejects missing or invalid values")
