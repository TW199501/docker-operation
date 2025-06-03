### docker-operation
使用docker與docker-compose 搭建佈署經驗

#### JWT加密語法
```
#### windows 不可讀
$bytes = New-Object Byte[] 16
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
[Convert]::ToBase64String($bytes)

##### windows 可讀
$length = 16
$chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
$randomString = -join ($chars.ToCharArray() | Get-Random -Count $length)
$randomString

##### linux 可讀
openssl rand -base64 32
```

####