using System;
using System.Runtime.InteropServices;
using System.Text;

namespace BAMCIS.CredentialManager
{
    /// <summary>
    /// Provides a .NET wrapper around the Win32 CREDENTIAL struct
    /// </summary>
    public class Credential
    {
        #region Private Fields

        private string _Comment;
        private CREDENTIAL_ATTRIBUTE[] _Attributes;
        private string _TargetAlias;
        private string _UserName;

        #endregion

        #region Public Properties

        /// <summary>
        /// A bit member that identifies characteristics of the credential. Undefined bits should be initialized as zero and not otherwise altered to permit future enhancement.
        /// </summary>
        public CredentialFlags Flags { get; set; }

        /// <summary>
        /// The type of the credential. This member cannot be changed after the credential is created.
        /// </summary>
        public CredentialType Type { get; set; }

        /// <summary>
        /// The name of the credential. The TargetName and Type members uniquely identify the credential. This member cannot be changed after the credential is created. Instead, the credential with the old name should be deleted and the credential with the new name created.
        /// </summary>
        public string TargetName { get; private set; }

        /// <summary>
        /// A string comment from the user that describes this credential. This member cannot be longer than CRED_MAX_STRING_LENGTH (256) characters.
        /// </summary>
        public string Comment
        {
            get
            {
                return this._Comment;
            }
            set
            {
                if (!String.IsNullOrEmpty(value))
                {
                    if (value.Length <= 256)
                    {
                        this._Comment = value;
                    }
                    else
                    {
                        throw new ArgumentOutOfRangeException("Comment", "The comment cannot be longer than 256 characters");
                    }
                }
                else
                {
                    this._Comment = String.Empty;
                }
            }
        }

        /// <summary>
        /// The time, in Coordinated Universal Time (Greenwich Mean Time), of the last modification of the credential. For write operations, the value of this member is ignored.
        /// </summary>
        public DateTime LastWritten { get; private set; }

        /// <summary>
        /// Secret data for the credential.
        /// </summary>
        public string CredentialBlob { get; private set; }

        /// <summary>
        /// Defines the persistence of this credential. This member can be read and written.
        /// </summary>
        public CredentialPersistence Persist { get; set; }

        /// <summary>
        /// Application-defined attributes that are associated with the credential. This member can be read and written.
        /// 
        /// This member is not currently supported
        /// </summary>
        public CREDENTIAL_ATTRIBUTE[] Attributes
        {
            get
            {
                return this._Attributes;
            }
            set
            {
                if (value != null)
                {
                    if (value.Length <= 64)
                    {
                        // this._Attributes = value;
                        throw new NotSupportedException("The attributes property is not supported.");
                    }
                    else
                    {
                        throw new ArgumentOutOfRangeException("Attributes", "The number of attributes cannot exceed 64.");
                    }
                }
                else
                {
                    this._Attributes = null;
                }
            }
        }

        /// <summary>
        /// Alias for the TargetName member. This member can be read and written. It cannot be longer than CRED_MAX_STRING_LENGTH (256) characters.
        /// </summary>
        public string TargetAlias
        {
            get
            {
                return this._TargetAlias;
            }
            set
            {
                if (!String.IsNullOrEmpty(value))
                {
                    if (value.Length <= 256)
                    {
                        this._TargetAlias = value;
                    }
                    else
                    {
                        throw new ArgumentOutOfRangeException("TargetAlias", "The TargetAlias cannot exceed 256 characters.");
                    }
                }
                else
                {
                    this._TargetAlias = String.Empty;
                }
            }
        }

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
        public string UserName
        {
            get
            {
                return this._UserName;
            }
            set
            {
                if (!String.IsNullOrEmpty(value))
                {
                    if (value.Length <= 513)
                    {
                        this._UserName = value;
                    }
                    else
                    {
                        throw new ArgumentOutOfRangeException("UserName", "The user name cannot exceed 513 characters.");
                    }
                }
                else
                {
                    this._UserName = String.Empty;
                }
            }
        }

        #endregion

        #region Constructors

        /// <summary>
        /// Basic constructor.
        /// </summary>
        /// <param name="userName"></param>
        /// <param name="secret"></param>
        /// <param name="target"></param>
        public Credential(string userName, string secret, string target)
        {
            // XP and Vista: 512; 
            // 7 and above: 5*512
            if (Environment.OSVersion.Version < new Version(6, 1) /* Windows 7 */)
            {
                if (!String.IsNullOrEmpty(secret) && Encoding.Unicode.GetByteCount(secret) > 512)
                {
                    throw new ArgumentOutOfRangeException("secret", "The secret cannot exceed 512 bytes.");
                }
            }
            else
            {
                if (!String.IsNullOrEmpty(secret) && Encoding.Unicode.GetByteCount(secret) > 512 * 5)
                {
                    throw new ArgumentOutOfRangeException("secret", "The secret cannot exceed 2560 bytes.");
                }
            }

            this.CredentialBlob = secret;
            this.UserName = userName;
            this.TargetName = target;

            this.Attributes = null;
            this.Comment = String.Empty;
        }

        /// <summary>
        /// Constructor with credential type.
        /// </summary>
        /// <param name="userName"></param>
        /// <param name="secret"></param>
        /// <param name="target"></param>
        /// <param name="type"></param>
        public Credential(string userName, string secret, string target, CredentialType type) : this(userName, secret, target)
        {
            this.Type = type;
        }

        /// <summary>
        /// Constructor with credential type and persistance.
        /// </summary>
        /// <param name="userName"></param>
        /// <param name="secret"></param>
        /// <param name="target"></param>
        /// <param name="type"></param>
        /// <param name="persist"></param>
        public Credential(string userName, string secret, string target, CredentialType type, CredentialPersistence persist) : this(userName, secret, target, type)
        {
            this.Persist = persist;
        }

        /// <summary>
        /// Constructor with flags.
        /// </summary>
        /// <param name="userName"></param>
        /// <param name="secret"></param>
        /// <param name="target"></param>
        /// <param name="flags"></param>
        public Credential(string userName, string secret, string target, CredentialFlags flags) : this(userName, secret, target)
        {
            this.Flags = flags;
        }

        /// <summary>
        /// Constructor with type and flags.
        /// </summary>
        /// <param name="userName"></param>
        /// <param name="secret"></param>
        /// <param name="target"></param>
        /// <param name="type"></param>
        /// <param name="flags"></param>
        public Credential(string userName, string secret, string target, CredentialType type, CredentialFlags flags) : this(userName, secret, target, type)
        {
            this.Flags = flags;
        }

        /// <summary>
        /// Constructor with type, persistance, and flags.
        /// </summary>
        /// <param name="userName"></param>
        /// <param name="secret"></param>
        /// <param name="target"></param>
        /// <param name="type"></param>
        /// <param name="persist"></param>
        /// <param name="flags"></param>
        public Credential(string userName, string secret, string target, CredentialType type, CredentialPersistence persist, CredentialFlags flags) : this(userName, secret, target, type, persist)
        {
            this.Flags = flags;
        }

        #endregion

        #region Internal Methods

        /// <summary>
        /// Creates a Win32 CREDENTIAL object from this object for writing to Credential Manager
        /// </summary>
        /// <returns></returns>
        internal CREDENTIAL ToWin32Credential()
        {
            CREDENTIAL NewCred = new CREDENTIAL();

            if (this.Attributes == null || this.Attributes.Length == 0)
            {
                NewCred.Attributes = IntPtr.Zero;
                NewCred.AttributeCount = 0;
            }
            else
            {
                // This won't get called, since in this version, the attributes property can't be set
                NewCred.Attributes = Marshal.AllocHGlobal(Marshal.SizeOf(this.Attributes));
                Marshal.StructureToPtr(this.Attributes, NewCred.Attributes, false);
                NewCred.AttributeCount = (UInt32)this.Attributes.Length;
            }

            NewCred.Comment = Marshal.StringToHGlobalUni(this.Comment);
            NewCred.TargetAlias = Marshal.StringToHGlobalUni(this.TargetAlias);
            NewCred.Type = this.Type;
            NewCred.Persist = this.Persist;
            NewCred.TargetName = Marshal.StringToHGlobalUni(this.TargetName);
            NewCred.CredentialBlob = Marshal.StringToHGlobalUni(this.CredentialBlob);
            NewCred.CredentialBlobSize = (UInt32)Encoding.Unicode.GetByteCount(this.CredentialBlob);
            NewCred.UserName = Marshal.StringToHGlobalUni(this.UserName);
            NewCred.Flags = this.Flags;

            return NewCred;
        }

        /// <summary>
        /// Creates a credential object from a marshaled Win32 CREDENTIAL object
        /// </summary>
        /// <param name="credential">The credential object to convert</param>
        /// <returns></returns>
        internal static Credential FromWin32Credential(CREDENTIAL credential)
        {
            string Target = Marshal.PtrToStringUni(credential.TargetName);
            string UserName = Marshal.PtrToStringUni(credential.UserName);
            string Secret = null;

            if (credential.CredentialBlob != IntPtr.Zero)
            {
                Secret = Marshal.PtrToStringUni(credential.CredentialBlob, (int)credential.CredentialBlobSize / 2);
            }

            Credential NewCred = new Credential(UserName, Secret, Target)
            {
                Comment = Marshal.PtrToStringUni(credential.Comment),
                Flags = credential.Flags,
                LastWritten = ToDateTime(credential.LastWritten),
                Persist = credential.Persist,
                TargetAlias = Marshal.PtrToStringUni(credential.TargetAlias),
                Type = credential.Type
            };


            /* This isn't supported yet since the CREDENTIAL_ATTRIBUTE struct isn't necessarily a constant size
            if (credential.Attributes != IntPtr.Zero)
            {
                NewCred.Attributes = new CREDENTIAL_ATTRIBUTE[credential.AttributeCount];

                for (int i = 0; i < credential.AttributeCount; i++)
                {
                    NewCred.Attributes[i] = Marshal.PtrToStructure<CREDENTIAL_ATTRIBUTE>(new IntPtr(credential.Attributes.ToInt64() + i * Marshal.SizeOf<CREDENTIAL_ATTRIBUTE>()));
                }
            }
            */

            return NewCred;
        }

        #endregion

        #region Private Methods

        /// <summary>
        /// https://stackoverflow.com/questions/6083733/not-being-able-to-convert-from-filetime-windows-time-to-datetime-i-get-a-dif
        /// </summary>
        /// <param name="time"></param>
        /// <returns></returns>
        private static DateTime ToDateTime(System.Runtime.InteropServices.ComTypes.FILETIME time)
        {
            UInt64 High = (UInt64)time.dwHighDateTime;
            UInt32 Low = (UInt32)time.dwLowDateTime;

            Int64 fileTime = (Int64)((High << 32) + Low);

            try
            {
                return DateTime.FromFileTimeUtc(fileTime);
            }
            catch (Exception)
            {
                return DateTime.FromFileTimeUtc(0xFFFFFFFF);
            }
        }

        #endregion
    }
}
