using System;
using System.Runtime.InteropServices;

namespace BAMCIS.CredentialManager
{
    /// <summary>
    /// The CREDENTIAL structure contains an individual credential.
    /// </summary>
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL
    {
        /// <summary>
        /// A bit member that identifies characteristics of the credential. Undefined bits should be initialized as zero and not otherwise altered to permit future enhancement.
        /// </summary>
        public CredentialFlags Flags;

        /// <summary>
        /// The type of the credential. This member cannot be changed after the credential is created.
        /// </summary>
        public CredentialType Type;

        /// <summary>
        /// The name of the credential. The TargetName and Type members uniquely identify the credential. This member cannot be changed after the credential is created. Instead, the credential with the old name should be deleted and the credential with the new name created.
        /// </summary>
        public IntPtr TargetName;

        /// <summary>
        /// A string comment from the user that describes this credential. This member cannot be longer than CRED_MAX_STRING_LENGTH (256) characters.
        /// </summary>
        public IntPtr Comment;

        /// <summary>
        /// The time, in Coordinated Universal Time (Greenwich Mean Time), of the last modification of the credential. For write operations, the value of this member is ignored.
        /// </summary>
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;

        /// <summary>
        /// The size, in bytes, of the CredentialBlob member. This member cannot be larger than CRED_MAX_CREDENTIAL_BLOB_SIZE (512) bytes.
        /// </summary>
        public UInt32 CredentialBlobSize;

        /// <summary>
        /// Secret data for the credential. The CredentialBlob member can be both read and written.
        ///
        /// If the Type member is CRED_TYPE_DOMAIN_PASSWORD, this member contains the plaintext Unicode password for UserName.The CredentialBlob and CredentialBlobSize members do not include a trailing zero character.Also, for CRED_TYPE_DOMAIN_PASSWORD, this member can only be read by the authentication packages.
        ///
        /// If the Type member is CRED_TYPE_DOMAIN_CERTIFICATE, this member contains the clear test Unicode PIN for UserName.The CredentialBlob and CredentialBlobSize members do not include a trailing zero character. Also, this member can only be read by the authentication packages.
        ///
        /// If the Type member is CRED_TYPE_GENERIC, this member is defined by the application.
        ///
        /// Credentials are expected to be portable. Applications should ensure that the data in CredentialBlob is portable.The application defines the byte-endian and alignment of the data in CredentialBlob.
        /// </summary>
        public IntPtr CredentialBlob;

        /// <summary>
        /// Defines the persistence of this credential. This member can be read and written.
        /// </summary>
        public CredentialPersistence Persist;

        /// <summary>
        /// The number of application-defined attributes to be associated with the credential. This member can be read and written. Its value cannot be greater than CRED_MAX_ATTRIBUTES (64).
        /// </summary>
        public UInt32 AttributeCount;

        /// <summary>
        /// Application-defined attributes that are associated with the credential. This member can be read and written.
        /// </summary>
        public IntPtr Attributes;

        /// <summary>
        /// Alias for the TargetName member. This member can be read and written. It cannot be longer than CRED_MAX_STRING_LENGTH (256) characters.
        /// </summary>
        public IntPtr TargetAlias;

        /// <summary>
        /// The user name of the account used to connect to TargetName.
        ///
        /// If the credential Type is CRED_TYPE_DOMAIN_PASSWORD, this member can be either a DomainName\UserName or a UPN.
        ///
        /// If the credential Type is CRED_TYPE_DOMAIN_CERTIFICATE, this member must be a marshaled certificate reference created by calling CredMarshalCredential with a CertCredential.
        ///
        /// If the credential Type is CRED_TYPE_GENERIC, this member can be non-NULL, but the credential manager ignores the member.
        ///
        /// This member cannot be longer than CRED_MAX_USERNAME_LENGTH (513) characters.
        /// </summary>
        public IntPtr UserName;
    }
}
