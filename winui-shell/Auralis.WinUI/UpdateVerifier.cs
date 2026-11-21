using System.Security.Cryptography;

namespace Auralis.WinUI;

internal static class UpdateVerifier
{
    internal static async Task<bool> VerifyAsync(Stream input,long expectedSize,string expectedSha256,CancellationToken token)
    {
        if (expectedSize<=0 || expectedSize>UpdatePolicy.MaximumInstallerBytes || expectedSha256.Length!=64 || !expectedSha256.All(Uri.IsHexDigit)) return false;
        using var hash=IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        byte[] buffer=new byte[65536]; long size=0;
        while (true)
        {
            int count=await input.ReadAsync(buffer,token);
            if (count==0) break;
            size+=count;
            if (size>expectedSize) return false;
            hash.AppendData(buffer,0,count);
        }
        return size==expectedSize && CryptographicOperations.FixedTimeEquals(hash.GetHashAndReset(),Convert.FromHexString(expectedSha256));
    }
}
