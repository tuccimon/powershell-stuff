
function Get-RandomVoice {
    $random = Get-Random -Minimum 1 -Maximum 100
    if ($random -ge 51) {
        return 'Microsoft David Desktop'
    }
    else {
        return 'Microsoft Zira Desktop'
    }
}

Add-Type -AssemblyName System.Speech

# seems like you can only have so many of the same voice run at the same time
$VoicesCount = 50
$Message = "we are borg. you will be assimilated. resistance is futile."

# setup voices
1..$VoicesCount | % {
    iex "`$Synth$_ = New-Object -TypeName System.Speech.Synthesis.SpeechSynthesizer"
    iex "`$Synth$_.SelectVoice(`"$(Get-RandomVoice)`")"
}

# now altogether speak like creep borg
1..$VoicesCount | % {iex "`$null = `$Synth$_.SpeakAsync('$Message')"}
