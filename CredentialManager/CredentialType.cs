namespace BAMCIS.CredentialManager
{
    /// <summary>
    /// The type of the credential. This member cannot be changed after the credential is created. The following values are valid.
    /// </summary>
    public enum CredentialType : uint
    {
        /// <summary>
        /// The credential is a generic credential. The credential will not be used by any particular authentication package. The credential will be stored securely but has no other significant characteristics.
        /// </summary>
        CRED_TYPE_GENERIC = 0x1,

        /// <summary>
        /// The credential is a password credential and is specific to Microsoft's authentication packages. The NTLM, Kerberos, and Negotiate authentication packages will automatically use this credential when connecting to the named target.
        /// </summary>
        CRED_TYPE_DOMAIN_PASSWORD = 0x2,

        /// <summary>
        /// The credential is a certificate credential and is specific to Microsoft's authentication packages. The Kerberos, Negotiate, and Schannel authentication packages automatically use this credential when connecting to the named target.
        /// </summary>
        CRED_TYPE_DOMAIN_CERTIFICATE = 0x3,

        /// <summary>
        /// This value is no longer supported.
        ///
        /// Windows Server 2003 and Windows XP:  The credential is a password credential and is specific to authentication packages from Microsoft. The Passport authentication package will automatically use this credential when connecting to the named target.
        /// </summary>
        CRED_TYPE_DOMAIN_VISIBLE_PASSWORD = 0x4,

        /// <summary>
        /// The credential is a certificate credential that is a generic authentication package.
        /// </summary>
        CRED_TYPE_GENERIC_CERTIFICATE = 0x5,

        /// <summary>
        /// The credential is supported by extended Negotiate packages.
        /// </summary>
        CRED_TYPE_DOMAIN_EXTENDED = 0x6,

        /// <summary>
        /// The maximum number of supported credential types.
        /// </summary>
        CRED_TYPE_MAXIMUM = 0x7,

        /// <summary>
        /// The extended maximum number of supported credential types that now allow new applications to run on older operating systems.
        /// </summary>
        CRED_TYPE_MAXIMUM_EX = CRED_TYPE_MAXIMUM + 1000
    }
}
