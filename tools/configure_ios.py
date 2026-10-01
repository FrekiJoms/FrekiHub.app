"""Wire the checked-in ActivityKit extension into the generated Xcode project."""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parents[1]
project = root / 'ios/Runner.xcodeproj/project.pbxproj'
text = project.read_text(encoding='utf-8-sig')
def oid(n):
    return f'F0E11A00000000000000{n:04X}'
def section(name, value):
    global text
    marker = f'/* End {name} section */'
    text = text.replace(marker, value + '\n' + marker)

if '/* FrekiHub Session Widget */' not in text:
    section('PBXBuildFile', f'''
        {oid(1)} = {{isa = PBXBuildFile; fileRef = {oid(4)}; }};
        {oid(2)} = {{isa = PBXBuildFile; fileRef = {oid(4)}; }};
        {oid(3)} = {{isa = PBXBuildFile; fileRef = {oid(5)}; }};
        {oid(6)} = {{isa = PBXBuildFile; fileRef = {oid(7)}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};''')
    section('PBXFileReference', f'''
        {oid(4)} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Shared/SessionAttributes.swift; sourceTree = "<group>"; }};
        {oid(5)} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SessionWidget/SessionWidget.swift; sourceTree = "<group>"; }};
        {oid(7)} = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; path = SessionWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; }};''')
    section('PBXContainerItemProxy', f'''
        {oid(8)} = {{isa = PBXContainerItemProxy; containerPortal = 97C146E61CF9000F007C117D; proxyType = 1; remoteGlobalIDString = {oid(9)}; remoteInfo = SessionWidget; }};''')
    section('PBXCopyFilesBuildPhase', f'''
        {oid(10)} = {{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({oid(6)}, ); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0; }};''')
    section('PBXNativeTarget', f'''
        {oid(9)} /* FrekiHub Session Widget */ = {{isa = PBXNativeTarget; buildConfigurationList = {oid(11)}; buildPhases = ({oid(12)}, {oid(13)}, {oid(14)}, ); buildRules = (); dependencies = (); name = SessionWidget; productName = SessionWidget; productReference = {oid(7)}; productType = "com.apple.product-type.app-extension"; }};''')
    section('PBXSourcesBuildPhase', f'''
        {oid(12)} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({oid(2)}, {oid(3)}, ); runOnlyForDeploymentPostprocessing = 0; }};''')
    section('PBXFrameworksBuildPhase', f'''
        {oid(13)} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};''')
    section('PBXResourcesBuildPhase', f'''
        {oid(14)} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};''')
    section('PBXTargetDependency', f'''
        {oid(15)} = {{isa = PBXTargetDependency; target = {oid(9)}; targetProxy = {oid(8)}; }};''')
    for n, name in enumerate(['Debug', 'Release', 'Profile'], 16):
        section('XCBuildConfiguration', f'''
        {oid(n)} = {{isa = XCBuildConfiguration; buildSettings = {{APPLICATION_EXTENSION_API_ONLY = YES; CLANG_ENABLE_MODULES = YES; CODE_SIGN_ENTITLEMENTS = SessionWidget/SessionWidget.entitlements; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = SessionWidget/Info.plist; IPHONEOS_DEPLOYMENT_TARGET = 16.1; LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks", ); MARKETING_VERSION = 1.0.0; PRODUCT_BUNDLE_IDENTIFIER = com.frekihub.frekiHub.SessionWidget; PRODUCT_NAME = "$(TARGET_NAME)"; SDKROOT = iphoneos; SKIP_INSTALL = YES; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2"; }}; name = {name}; }};''')
    section('XCConfigurationList', f'''
        {oid(11)} = {{isa = XCConfigurationList; buildConfigurations = ({oid(16)}, {oid(17)}, {oid(18)}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};''')
    text = text.replace('mainGroup = 97C146E51CF9000F007C117D;', 'mainGroup = 97C146E51CF9000F007C117D;')
    text = text.replace('97C146E51CF9000F007C117D = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (', f'97C146E51CF9000F007C117D = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n                {oid(4)}, {oid(5)},')
    text = text.replace('97C146EF1CF9000F007C117D /* Products */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (', f'97C146EF1CF9000F007C117D /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n                {oid(7)},')
    text = text.replace('74858FAF1ED2DC5600515810 /* AppDelegate.swift in Sources */,', f'74858FAF1ED2DC5600515810 /* AppDelegate.swift in Sources */,\n                {oid(1)},')
    text = text.replace('9705A1C41CF9048500538489 /* Embed Frameworks */,', f'9705A1C41CF9048500538489 /* Embed Frameworks */,\n                {oid(10)},')
    text = text.replace('\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = Runner;', f'\t\t\tdependencies = (\n                {oid(15)},\n\t\t\t);\n\t\t\tname = Runner;')
    text = text.replace('\t\t\ttargets = (', f'\t\t\ttargets = (\n                {oid(9)},')
    text = text.replace('INFOPLIST_FILE = Runner/Info.plist;', 'INFOPLIST_FILE = Runner/Info.plist;\n                CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;')
text = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 16.1;', text)
project.write_text(text, encoding='utf-8')
info = root / 'ios/Runner/Info.plist'
with info.open('rb') as f:
    value = plistlib.load(f)
value['NSSupportsLiveActivities'] = True
value['CFBundleDisplayName'] = 'FrekiHub'
value['CFBundleURLTypes'] = [{'CFBundleURLSchemes': ['frekihub']}]
with info.open('wb') as f:
    plistlib.dump(value, f, sort_keys=False)
print('ActivityKit extension configured.')
