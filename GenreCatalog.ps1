$script:genreCatalog = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'GenrePresets.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
function Get-CatalogGenreSettings([int]$index) {
    if ($index -lt 0 -or $index -ge $script:genreCatalog.Count) { throw 'Choose a valid genre.' }
    $entry=$script:genreCatalog[$index]
    $settings=Get-GenreSettings ([int]$entry.Base)
    foreach ($property in $entry.Set.PSObject.Properties) { $settings[$property.Name]=$property.Value }
    $settings.Genre=$entry.Name
    return (Test-Settings $settings)
}
function Initialize-GenreMenu {
    $ui.Preset.Items.Clear()
    foreach ($entry in $script:genreCatalog) { $ui.Preset.Items.Add([string]$entry.Name) | Out-Null }
    $ui.Preset.SelectedIndex=0
}
