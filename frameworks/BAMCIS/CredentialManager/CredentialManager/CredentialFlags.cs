using System;

namespace BAMCIS.CredentialManager
{
    /// <summary>
    /// A bit member that identifies characteristics of the credential. Undefined bits should be initialized as zero and not otherwise altered to permit future enhancement.
    /// </summary>
    [Flags]
    public enum CredentialFlags : uint
    {
        /// <summary>
        /// Bit set if the credential does not persist the CredentialBlob and the credential has not been written during this logon session. This bit is ignored on input and is set automatically when queried.
        ///
        /// If Type is CRED_TYPE_DOMAIN_CERTIFICATE, the CredentialBlob is not persisted across logon sessions because the PIN of a certificate is very sensitive information. Indeed, when the credential is written to credential manager, the PIN is passed to the CSP associated with the certificate. The CSP will enforce a PIN retention policy appropriate to the certificate.
        ///
        /// If Type is CRED_TYPE_DOMAIN_PASSWORD or CRED_TYPE_DOMAIN_CERTIFICATE, an authentication package always fails an authentication attempt when using credentials marked as CRED_FLAGS_PROMPT_NOW.The application(typically through the key ring UI) prompts the user for the password.The application saves the credential and retries the authentication. Because the credential has been recently written, the authentication package now gets a credential that is not marked as CRED_FLAGS_PROMPT_NOW.
        /// </summary>
        CRED_FLAGS_PROMPT_NOW = 0x2,

        /// <summary>
        /// Bit is set if this credential has a TargetName member set to the same value as the UserName member. Such a credential is one designed to store the CredentialBlob for a specific user. For more information, see the CredMarshalCredential function.
        ///
        /// This bit can only be specified if Type is CRED_TYPE_DOMAIN_PASSWORD or CRED_TYPE_DOMAIN_CERTIFICATE.
        /// </summary>
        CRED_FLAGS_USERNAME_TARGET = 0x4
    }
}
