package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func caskFromJSON(t *testing.T, raw string) caskInfo {
	t.Helper()
	var c caskInfo
	if err := json.Unmarshal([]byte(raw), &c); err != nil {
		t.Fatal(err)
	}
	return c
}

func TestCaskAppNames(t *testing.T) {
	plain := caskFromJSON(t, `{"token": "a", "artifacts": [{"uninstall": [{"quit": "x"}]}, {"app": ["Foo.app"]}, {"zap": [{"trash": "~/x"}]}]}`)
	if names, ok := plain.appNames(); !ok || !reflect.DeepEqual(names, []string{"Foo.app"}) {
		t.Errorf("plain: %v %v", names, ok)
	}
	target := caskFromJSON(t, `{"token": "b", "artifacts": [{"app": ["Build/Foo Beta.app", {"target": "Foo.app"}]}]}`)
	if names, ok := target.appNames(); !ok || !reflect.DeepEqual(names, []string{"Foo.app"}) {
		t.Errorf("target: %v %v", names, ok)
	}
	pkg := caskFromJSON(t, `{"token": "c", "artifacts": [{"pkg": ["Install.pkg"]}, {"app": ["Bar.app"]}]}`)
	if _, ok := pkg.appNames(); ok {
		t.Error("a cask with a pkg counts as a plain app install")
	}
}

func TestCompareVersions(t *testing.T) {
	for _, tc := range []struct {
		a, b string
		want int
	}{
		{"1.10.0", "1.9.9", 1},
		{"1.2", "1.2.0", 0},
		{"2.0", "10.0", -1},
		{"1.0", "1.0b2", 1},
		{"1.0b2", "1.0b10", -1},
		{"124.0.6367.60", "124.0.6367.207", -1},
		{"2024.10", "2024.9.30", 1},
	} {
		if got := compareVersions(tc.a, tc.b); got != tc.want {
			t.Errorf("compareVersions(%q, %q) = %d, want %d", tc.a, tc.b, got, tc.want)
		}
	}
}

func TestNewerThanAppUsesADottedBuildNumberToo(t *testing.T) {
	for _, tc := range []struct {
		available, short, build string
		want                    bool
	}{
		{"3.0.21", "3.0.20", "3.0.20", true},
		{"3.0.12", "3", "3.0.12", false}, // short version too coarse; the build tells
		{"1.6", "1.5", "4521", true},     // a plain build counter says nothing
		{"1.5", "1.5", "4521", false},
		{"2.0", "", "", false}, // unknown installed version: never guess
	} {
		if got := newerThanApp(tc.available, tc.short, tc.build); got != tc.want {
			t.Errorf("newerThanApp(%q, %q, %q) = %v, want %v", tc.available, tc.short, tc.build, got, tc.want)
		}
	}
}

func TestTakeoverRowsOfferOnlyClearNewerMatches(t *testing.T) {
	index := []caskInfo{
		caskFromJSON(t, `{"token": "vlc", "name": ["VLC"], "version": "3.0.21,abc", "artifacts": [{"app": ["VLC.app"]}]}`),
		caskFromJSON(t, `{"token": "same", "version": "2.0", "artifacts": [{"app": ["Same.app"]}]}`),
		caskFromJSON(t, `{"token": "selfupdating", "version": "9.0", "auto_updates": true, "artifacts": [{"app": ["Self.app"]}]}`),
		caskFromJSON(t, `{"token": "withpkg", "version": "9.0", "artifacts": [{"pkg": ["x.pkg"]}, {"app": ["Pkg.app"]}]}`),
		caskFromJSON(t, `{"token": "firefox", "version": "130.0", "artifacts": [{"app": ["Firefox.app"]}]}`),
		caskFromJSON(t, `{"token": "firefox@beta", "version": "131.0b1", "artifacts": [{"app": ["Firefox.app"]}]}`),
		caskFromJSON(t, `{"token": "twin-a", "version": "5.0", "artifacts": [{"app": ["Twin.app"]}]}`),
		caskFromJSON(t, `{"token": "twin-b", "version": "5.0", "artifacts": [{"app": ["Twin.app"]}]}`),
		caskFromJSON(t, `{"token": "managed", "version": "9.0", "artifacts": [{"app": ["Managed.app"]}]}`),
		caskFromJSON(t, `{"token": "gone", "version": "9.0", "disabled": true, "artifacts": [{"app": ["Gone.app"]}]}`),
		caskFromJSON(t, `{"token": "apple", "version": "9.0", "artifacts": [{"app": ["Pages.app"]}]}`),
	}
	apps := []localApp{
		{FileName: "VLC.app", BundleID: "org.videolan.vlc", Short: "3.0.20", Build: "3.0.20"},
		{FileName: "Same.app", Short: "2.0"},
		{FileName: "Self.app", Short: "1.0"},
		{FileName: "Pkg.app", Short: "1.0"},
		{FileName: "Firefox.app", Short: "129.0"},
		{FileName: "Twin.app", Short: "1.0"},
		{FileName: "Managed.app", Short: "1.0"},
		{FileName: "Gone.app", Short: "1.0"},
		{FileName: "Pages.app", BundleID: "com.apple.iWork.Pages", Short: "1.0"},
		{FileName: "Unknown.app", Short: "1.0"},
	}
	got := takeoverRows(apps, index, map[string]bool{"managed": true}, map[string]bool{})
	want := []Row{
		{Kind: "takeover", ID: "firefox", Name: "Firefox", Installed: "129.0", Available: "130.0", Note: "replaces your copy"},
		{Kind: "takeover", ID: "vlc", Name: "VLC", Installed: "3.0.20", Available: "3.0.21", Note: "replaces your copy"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %#v\nwant %#v", got, want)
	}

	// An app Homebrew already installed is never offered again.
	if got := takeoverRows(apps[:1], index, map[string]bool{}, map[string]bool{"VLC.app": true}); len(got) != 0 {
		t.Errorf("managed app offered: %#v", got)
	}
}

func TestParsePlistStringsReadsTopLevelStrings(t *testing.T) {
	xml := `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDocumentTypes</key>
	<array><dict><key>CFBundleShortVersionString</key><string>nested</string></dict></array>
	<key>CFBundleIdentifier</key>
	<string>org.example.app</string>
	<key>LSRequiresNativeExecution</key>
	<true/>
	<key>CFBundleShortVersionString</key>
	<string>1.2.3</string>
	<key>CFBundleVersion</key>
	<string>45</string>
</dict>
</plist>`
	got := parsePlistStrings([]byte(xml))
	want := map[string]string{"CFBundleIdentifier": "org.example.app", "CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "45"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestParseCaskIndexPlainAndSigned(t *testing.T) {
	plain := `[{"token": "vlc", "version": "3.0.21"}]`
	index, err := parseCaskIndex([]byte(plain))
	if err != nil || len(index) != 1 || index[0].Token != "vlc" {
		t.Fatalf("plain: %v %v", index, err)
	}
	payload, _ := json.Marshal(plain)
	signed := `{"payload": ` + string(payload) + `, "signatures": []}`
	index, err = parseCaskIndex([]byte(signed))
	if err != nil || len(index) != 1 || index[0].Version != "3.0.21" {
		t.Fatalf("signed: %v %v", index, err)
	}
	if _, err := parseCaskIndex([]byte(`{"other": 1}`)); err == nil {
		t.Error("a wrong shape parsed")
	}
}

func TestScanApplicationsSkipsAppStoreAppsAndSymlinks(t *testing.T) {
	root := t.TempDir()
	makeApp := func(path, version string) {
		t.Helper()
		if err := os.MkdirAll(filepath.Join(path, "Contents"), 0o755); err != nil {
			t.Fatal(err)
		}
		plist := "<plist><dict><key>CFBundleShortVersionString</key><string>" + version + "</string></dict></plist>"
		if err := os.WriteFile(filepath.Join(path, "Contents", "Info.plist"), []byte(plist), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	makeApp(filepath.Join(root, "VLC.app"), "3.0.20")
	makeApp(filepath.Join(root, "Utilities", "Tool.app"), "1.0")
	makeApp(filepath.Join(root, "Utilities", "Deeper", "TooDeep.app"), "1.0")
	makeApp(filepath.Join(root, "Store.app"), "2.0")
	if err := os.MkdirAll(filepath.Join(root, "Store.app", "Contents", "_MASReceipt"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(root, "VLC.app"), filepath.Join(root, "Link.app")); err != nil {
		t.Fatal(err)
	}

	saved := readInfoPlist
	readInfoPlist = func(path string) (map[string]string, error) {
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		return parsePlistStrings(data), nil
	}
	t.Cleanup(func() { readInfoPlist = saved })

	var names []string
	for _, app := range scanApplications([]string{root, filepath.Join(root, "missing")}) {
		names = append(names, app.FileName+"@"+app.Short)
	}
	if strings.Join(names, ",") != "Tool.app@1.0,VLC.app@3.0.20" && strings.Join(names, ",") != "VLC.app@3.0.20,Tool.app@1.0" {
		t.Errorf("apps found: %v", names)
	}
}
