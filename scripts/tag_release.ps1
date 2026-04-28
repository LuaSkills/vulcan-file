<#
.SYNOPSIS
Create and push an annotated Git tag for the vulcan-file LuaSkill release.
创建并推送用于 vulcan-file LuaSkill 发布的带注释 Git 标签。
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$tag = if ($Version.StartsWith("v")) { $Version } else { "v$Version" }

Write-Host "Creating annotated tag: $tag"
git tag -a $tag -m "Release $tag"
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Pushing tag to origin: $tag"
git push origin $tag
exit $LASTEXITCODE
