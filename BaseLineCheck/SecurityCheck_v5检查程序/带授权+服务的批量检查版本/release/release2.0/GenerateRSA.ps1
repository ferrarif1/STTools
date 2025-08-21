$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider 2048
$rsa.PersistKeyInCsp = $false
$rsa.ToXmlString($true)  | Set-Content private_key.xml -Encoding UTF8
$rsa.ToXmlString($false) | Set-Content public_key.xml  -Encoding UTF8