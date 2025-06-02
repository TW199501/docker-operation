## windows 不可讀
$bytes = New-Object Byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
[Convert]::ToBase64String($bytes)

## windows 可讀
$length = 32
$chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
$randomString = -join ($chars.ToCharArray() | Get-Random -Count $length)
$randomString