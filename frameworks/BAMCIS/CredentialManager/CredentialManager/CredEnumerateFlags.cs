using System;

namespace BAMCIS.CredentialManager
{
    /// <summary>
    /// Flags that control the function's operation.
    /// </summary>
    [Flags]
    public enum CredEnumerateFlags : uint
    {
        /// <summary>
        /// This function enumerates all of the credentials in the user's credential set. The target name of each credential is returned in the "namespace:attribute=target" format. If this flag is set and the Filter parameter is not NULL, the function fails and returns ERROR_INVALID_FLAGS.
        /// </summary>
        CRED_ENUMERATE_ALL_CREDENTIALS = 0x1
    }
}
