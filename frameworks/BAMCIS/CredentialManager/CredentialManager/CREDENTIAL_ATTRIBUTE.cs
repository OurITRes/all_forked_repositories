using System;
using System.Runtime.InteropServices;

namespace BAMCIS.CredentialManager
{
    /// <summary>
    /// The CREDENTIAL_ATTRIBUTE structure contains an application-defined attribute of the credential. An attribute is a keyword-value pair. It is up to the application to define the meaning of the attribute.
    /// </summary>
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL_ATTRIBUTE
    {
        /// <summary>
        /// Name of the application-specific attribute. Names should be of the form <CompanyName>_<Name>.
        ///
        /// This member cannot be longer than CRED_MAX_STRING_LENGTH(256) characters.
        /// </summary>
        IntPtr Keyword;

        /// <summary>
        /// Identifies characteristics of the credential attribute. This member is reserved and should be originally initialized as zero and not otherwise altered to permit future enhancement.
        /// </summary>
        UInt32 Flags;

        /// <summary>
        /// Length of Value in bytes. This member cannot be larger than CRED_MAX_VALUE_SIZE (256).
        /// </summary>
        UInt32 ValueSize;

        /// <summary>
        /// Data associated with the attribute. By convention, if Value is a text string, then Value should not include the trailing zero character and should be in UNICODE.
        ///
        /// Credentials are expected to be portable.The application should take care to ensure that the data in value is portable.It is the responsibility of the application to define the byte-endian and alignment of the data in Value.
        /// </summary>
        IntPtr Value;
    }
}
