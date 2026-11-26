param(
    [Parameter(Mandatory)] [string] $RarsJar,
    [Parameter(Mandatory)] [string] $OutputDirectory,
    [string] $Java = 'java'
)

$ErrorActionPreference = 'Stop'
$jar = (Resolve-Path -LiteralPath $RarsJar).ProviderPath
$output = (Resolve-Path -LiteralPath $OutputDirectory).ProviderPath
if (-not (Test-Path -LiteralPath $output -PathType Container)) { throw 'An output directory is required.' }
$stage1 = Join-Path $PSScriptRoot '../stage1'
$stage2 = Join-Path $PSScriptRoot '../stage2'
$common = 'mmio.s', 'ps2.s', 'video.s' | ForEach-Object { Join-Path $stage2 $_ }
$prefix = Join-Path $output ('.fw-' + [Guid]::NewGuid().ToString('N'))
$dataDump = "$prefix.data"
$initializer = "$prefix.s"
$gameSources = @((Join-Path $PSScriptRoot 'firmware.s')) + $common + @(
    (Join-Path $PSScriptRoot 'render.s'), (Join-Path $stage1 'game.s'), $initializer
)
$images = [ordered]@{
    'diag_mmio.mem' = @((Join-Path $stage2 'diag_mmio.s')) + $common
    'diag_vga.mem' = @((Join-Path $stage2 'diag_vga.s')) + $common
    'diag_key.mem' = @((Join-Path $stage2 'diag_key.s')) + $common
    'game.mem' = $gameSources
    'game_demo.mem' = $gameSources
}
$tableWords = (0x300 - 0x180) / 4

try {
    & $Java '-Djava.awt.headless=true' -jar $jar nc ae1 a mc Default dump .data HexText $dataDump `
        (Join-Path $stage1 'tables.s') (Join-Path $PSScriptRoot 'assets.s')
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $dataDump -PathType Leaf)) {
        throw 'RARS failed to export the game tables.'
    }
    $dataWords = [IO.File]::ReadAllLines($dataDump)
    if ($dataWords.Count -lt $tableWords -or ($dataWords -notmatch '^[0-9A-Fa-f]{8}$').Count -or
        $dataWords[0] -ne '13121110' -or $dataWords[32] -ne '08040600' -or
        $dataWords[$tableWords - 1] -ne '20202020') {
        throw 'Unexpected game table layout.'
    }
    # HexText can pad the final RAM block with zeros.
    for ($index = $tableWords; $index -lt $dataWords.Count; $index++) {
        if ($dataWords[$index] -ne '00000000') { throw 'Game tables exceed their reserved RAM area.' }
    }

    # The board has separate instruction ROM and data RAM. Embed RAM writes
    # in the boot program using the byte layout emitted by RARS.
    $assembly = [Collections.Generic.List[string]]::new()
    $assembly.Add('.text')
    $assembly.Add('.globl fw_init_data')
    $assembly.Add('fw_init_data:')
    $assembly.Add('    li t0, 0x180')
    for ($index = 0; $index -lt $tableWords; $index++) {
        $value = [Convert]::ToUInt32($dataWords[$index], 16)
        $upper = (([uint64]$value + 2048) -shr 12) -band 0xfffff
        $lower = $value -band 0xfff
        if ($lower -ge 2048) { $lower = [int]$lower - 4096 }
        $assembly.Add(('    lui t1, 0x{0:x}' -f $upper))
        $assembly.Add('    nop')
        $assembly.Add('    nop')
        $assembly.Add("    addi t1, t1, $lower")
        $assembly.Add("    sw t1, $($index * 4)(t0)")
    }
    $assembly.Add('    ret')
    $assembly.Add('.globl firmware_next_piece')
    $assembly.Add('firmware_next_piece:')

    foreach ($name in $images.Keys) {
        $binary = "$prefix.$name"
        $sources = $images[$name]
        if ($name -eq 'game.mem') {
            [IO.File]::WriteAllLines($initializer, ($assembly.ToArray() + '    j mmio_random_piece'),
                [Text.Encoding]::ASCII)
        } elseif ($name -eq 'game_demo.mem') {
            # O pieces give the operator a repeatable two-line clear.
            [IO.File]::WriteAllLines($initializer, ($assembly.ToArray() + '    li a0, 1' + '    ret'),
                [Text.Encoding]::ASCII)
        }
        # CompactTextAtZero limits text to 4 KiB. The firmware uses relative
        # branches/calls and explicit RAM/MMIO addresses, so its text dump
        # can be loaded at PC 0 after assembly in the default configuration.
        & $Java '-Djava.awt.headless=true' -jar $jar nc ae1 a mc Default dump .text HexText $binary @sources
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $binary -PathType Leaf)) {
            throw "RARS failed to export $name."
        }
        $words = [IO.File]::ReadAllLines($binary)
        if ($words.Count -lt 1 -or $words.Count -gt 4096 -or $words[0] -ne '00008137' -or
            ($words -notmatch '^[0-9A-Fa-f]{8}$').Count) {
            throw "Invalid ROM image: $name."
        }
        [IO.File]::WriteAllText($binary, ($words -join "`n") + "`n", [Text.Encoding]::ASCII)
    }

    foreach ($name in $images.Keys) {
        $destination = Join-Path $output $name
        Move-Item -LiteralPath "$prefix.$name" -Destination $destination -Force
        $wordCount = [IO.File]::ReadAllLines($destination).Count
        Write-Output "$name ($wordCount words) $((Get-FileHash -LiteralPath $destination).Hash)"
    }
} finally {
    $temporaryFiles = @($dataDump, $initializer) + @($images.Keys | ForEach-Object { "$prefix.$_" })
    foreach ($file in $temporaryFiles) {
        if (Test-Path -LiteralPath $file -PathType Leaf) { Remove-Item -LiteralPath $file }
    }
}
