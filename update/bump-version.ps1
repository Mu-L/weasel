param( [string]$tag, [string]$basetag, [switch]$updatelog, [switch]$h)
# -tag [new_tag], new tag shall be in format of ^\d+\.\d+\.\d+$ and greater than
#     the current one or $basetag
# -basetag [basetag name], specify the base tag(which shall be in format of ^\d+\.\d+\.\d+$),
#     default to be the latest number format tag name
# -updatelog, update CHANGELOG.md if this switch used
# -h, show help info

# get old version info from file, esp from build.bat
function get_old_version{
  param ([string]$filePath)
  $fileContent = Get-Content -Path $filePath;
  $version = @{};
  foreach ($line in $fileContent) {
    if ($version["major"] -eq $null -and $line -match 'VERSION_MAJOR=(\d+)') {
      $version["major"] = $matches[1];
    }
    if ($version["minor"] -eq $null -and $line -match 'VERSION_MINOR=(\d+)') {
      $version["minor"] = $matches[1];
    }
    if ($version["patch"] -eq $null -and $line -match 'VERSION_PATCH=(\d+)') {
      $version["patch"] = $matches[1];
    }
    if ($version["major"] -ne $null -and $version["minor"] -ne $null -and $version["patch"] -ne $null) {
      break;
    }
  }
  $version['str'] = $version["major"] + "." + $version["minor"] + "." + $version["patch"];
  return $version;
}

# parse new version info
function parse_new_version {
  param([string]$new_version)
  $version = @{};
  if ($new_version -match "^(\d+)\.(\d+)\.(\d+)$") {
    $version['major'] = $matches[1];
    $version['minor'] = $matches[2];
    $version['patch'] = $matches[3];
  }
  return $version;
}

# update bat file with param filePath, and tags 
function update_bat_file{
  param( [string]$filePath, $old_version, $new_version)
  $old_major, $old_minor, $old_patch = $old_version['major'], $old_version["minor"], $old_version["patch"];
  $new_major, $new_minor, $new_patch = $new_version['major'], $new_version["minor"], $new_version["patch"];
  $fileContent = Get-Content -Path $filePath -Raw;
  $fileContent = $fileContent -replace "VERSION_MAJOR=$old_major", "VERSION_MAJOR=$new_major";
  $fileContent = $fileContent -replace "VERSION_MINOR=$old_minor", "VERSION_MINOR=$new_minor";
  $fileContent = $fileContent -replace "VERSION_PATCH=$old_patch", "VERSION_PATCH=$new_patch";
  $fileContent | Out-File -FilePath $filePath -NoNewline -Encoding UTF8;
}

# update change log, work like clog-cli
function update_changelog {
  param( [string]$new_tag, [string]$old_tag)
  $commits = git log "$old_tag..HEAD" --pretty=format:"%s ([%an](https://github.com/rime/weasel/commit/%H))";
  # group commit logs
  $groupedCommits = @{
    build = @(); ci = @(); fix = @(); feat = @(); docs = @(); style = @();
    refactor = @(); test = @(); chore = @(); commit = @();
  };
  $groupedTitle = @{
    build = "Builds";
    ci = "Continuous Integration";
    fix = "Bug Fixes";
    feat = "Features";
    docs = "Documents";
    style = "Code Style";
    refactor = "Code Refactor";
    test = "Tests";
    chore = "Chores";
    commit = "Commits";
  };
  foreach ($commit in $commits) {
    if ($commit -match "^((?i)(build|ci|fix|feat|docs|style|refactor|test|chore)(\([^\)]+\))?):") {
      $prefix = $matches[2].ToLower();
      $groupedCommits[$prefix] += $commit;
    } else {
      $groupedCommits["commit"] += $commit;
    }
  }
  $changelog = "";
  foreach ($group in $groupedCommits.Keys) {
    if ($groupedCommits[$group].Count -gt 0) {
      $changelog += "`n#### " + $groupedTitle[$group] + "`n"
        foreach ($commit in $groupedCommits[$group]) {
          $msg = $commit -replace "^" + $group + ":", '';
          $changelog += "* $msg`n";
        }
    }
  }
  $currentDateTime = Get-Date -Format "yyyy-MM-dd";
  $fileContent = Get-Content -Path "CHANGELOG.md" -Raw -Encoding UTF8;
  $contentAdd = "<a name=`"$new_tag`"></a>`n" ;
  $contentAdd += "## [$new_tag](https://github.com/rime/weasel/compare/$old_tag...$new_tag)($currentDateTime)`n" ;
  $contentAdd += $changelog;
  Write-Host "`n" + $contentAdd + "`n"
  $fileContent = $contentAdd + "`n" + $fileContent;
  $fileContent | Out-File -FilePath "CHANGELOG.md" -NoNewline -Encoding UTF8;
}

# update appcast file, with regex patterns
function update_appcast_file {
  param( [string]$filePath, [string]$pat_orig, [string]$pat_replace)
  $fileContent = Get-Content -Path $filePath -Raw;
  $fileContent = $fileContent -replace $pat_orig, $pat_replace;
  $fileContent | Out-File -FilePath $filePath -NoNewline;
}
# test if cwd is weasel root
function is_weasel_root() {
  return (Test-Path -Path "weasel.sln") -and (Test-Path -Path ".git")
}
###############################################################################
# program now started
if ($h) {
  $info = @(
 "-tag [new_tag]`n`tnew tag shall be in format of ^\d+\.\d+\.\d+$ and greater than the current one or `$basetag",
 "-basetag [basetag name]`n`tspecify the base tag(which shall be in format of ^\d+\.\d+\.\d+$), default to be the latest number format tag name",
 "-updatelog`n`tupdate CHANGELOG.md if this switch used",
 "-h`n`tshow help info"
 )
 Write-Host ($info -join "`n");
 exit;
}
if (-not (is_weasel_root)) {
  Write-Host "Current directory is: $(Get-Location), it's not the weasel root directory"
  Write-Host "please run ``update/bump_version.ps1`` with parameters under the weasel root in Powershell";
  Write-Host "or run ``pwsh update/bump_version.ps1`` with parameters under weasel root in shell if yor're running Mac OS or Linux"
  exit;
}
# tag name not match rule, exit
if (-not ($tag -match '^\d+\.\d+\.\d+$')) {
  Write-Host "tag name not match rule '^\d+\.\d+\.\d+$'";
  Write-Host "please recheck it";
  exit;
}
# get old version
$old_version = get_old_version -filePath "build.bat";
$old_major, $old_minor, $old_patch = $old_version['major'], $old_version["minor"], $old_version["patch"];
# get new version
$new_version = parse_new_version -new_version $tag
if ($basetag -eq "") {
  $basetag = "$old_major.$old_minor.$old_patch"
}
if ($basetag -notmatch "^\d+\.\d+\.\d+$") {
  Write-Host "basetag format is not correct, it shall be in format of '^\d+\.\d+\.\d+$'"
  Write-Host "please recheck it";
  exit;
}

# check new version is greater than the current one
if ($tag -eq $old_version["str"]) {
  Write-Host "the new tag: $tag is the same with the old one:" $old_version["str"];
  exit;
} elseif ($tag -lt $old_version["str"]) {
  Write-Host "$tag is older version than " $old_version['str']", please recheck your target version.";
  exit;
}
Write-Host "bump version to $tag ... "
#get date-time string in english date-time format
$CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
$currentDateTime = (Get-Date).ToString("ddd, dd MMM yyyy HH:mm:ss K", $CurrentCulture)

#update appcast files
update_appcast_file -filePath "update/appcast.xml" -pat_orig "$old_major\.$old_minor\.$old_patch" -pat_replace $tag
update_appcast_file -filePath "update/appcast.xml" -pat_orig "<pubDate>.*?</pubDate>" -pat_replace "<pubDate>$currentDateTime</pubDate>"
Write-Host "update/appcast.xml updated"
update_appcast_file -filePath "update/testing-appcast.xml" -pat_orig "$old_major\.$old_minor\.$old_patch" -pat_replace $tag
update_appcast_file -filePath "update/testing-appcast.xml" -pat_orig "<pubDate>.*?</pubDate>" -pat_replace "<pubDate>$currentDateTime</pubDate>"
Write-Host "update/testing-appcast.xml updated"
#update bat files
update_bat_file -filePath "build.bat" -old_version $old_version -new_version $new_version
Write-Host "build.bat updated"
update_bat_file -filePath "xbuild.bat" -old_version $old_version -new_version $new_version
Write-Host "xbuild.bat updated"
#update CHANGELOG.md
if ($updatelog) {
  update_changelog -new_tag $tag -old_tag $basetag
  & git add CHANGELOG.md
  Write-Host "CHANGELOG.md updated"
}
#commit changes and make a new tag
$release_message = "chore(release): $tag :tada:"
$release_tag = $tag
& git add update/*.xml build.bat xbuild.bat
& git commit --message $release_message
& git tag --annotate $release_tag --message $release_message
