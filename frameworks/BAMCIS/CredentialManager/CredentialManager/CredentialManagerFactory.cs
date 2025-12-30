using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace BAMCIS.CredentialManager
{
    /// <summary>
    /// Provides an interface to the Win32 Credential Manager API to read, write, enumerate, and delete stored credentials
    /// </summary>
    public static class CredentialManagerFactory
    {
        #region Win32 Functions

        /// <summary>
        /// The CredRead function reads a credential from the user's credential set. The credential set used is the one associated with the logon session of the current token. The token must not have the user's SID disabled.
        /// </summary>
        /// <param name="targetName">Pointer to a null-terminated string that contains the name of the credential to read.</param>
        /// <param name="type">Type of the credential to read. Type must be one of the CRED_TYPE_* defined types.</param>
        /// <param name="flags">Currently reserved and must be zero.</param>
        /// <param name="credential">Pointer to a single allocated block buffer to return the credential. Any pointers contained within the buffer are pointers to locations within this single allocated block. The single returned buffer must be freed by calling CredFree.</param>
        /// <returns></returns>
        [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredRead(string targetName, CredentialType type, int flags, out IntPtr credential);

        /// <summary>
        /// The CredWrite function creates a new credential or modifies an existing credential in the user's credential set. The new credential is associated with the logon session of the current token. The token must not have the user's security identifier (SID) disabled.
        /// </summary>
        /// <param name="credential">A pointer to the CREDENTIAL structure to be written.</param>
        /// <param name="flags">Flags that control the function's operation. </param>
        /// <returns></returns>
        [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredWrite([In] ref CREDENTIAL credential, [In] UInt32 flags);

        /// <summary>
        /// The CredEnumerate function enumerates the credentials from the user's credential set. The credential set used is the one associated with the logon session of the current token. The token must not have the user's SID disabled.
        /// </summary>
        /// <param name="filter">Pointer to a null-terminated string that contains the filter for the returned credentials. Only credentials with a TargetName matching the filter will be returned. The filter specifies a name prefix followed by an asterisk. For instance, the filter "FRED*" will return all credentials with a TargetName beginning with the string "FRED".
        /// If NULL is specified, all credentials will be returned.</param>
        /// <param name="flag">The value of this parameter can be zero or more of the following values combined with a bitwise-OR operation.</param>
        /// <param name="count">Count of the credentials returned in the Credentials array.</param>
        /// <param name="pCredentials">Pointer to an array of pointers to credentials. The returned credential is a single allocated block. Any pointers contained within the buffer are pointers to locations within this single allocated block. The single returned buffer must be freed by calling CredFree.</param>
        /// <returns></returns>
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool CredEnumerate(string filter, UInt32 flag, out UInt32 count, out IntPtr pCredentials);

        /// <summary>
        /// The CredFree function frees a buffer returned by any of the credentials management functions.
        /// </summary>
        /// <param name="buffer">Pointer to the buffer to be freed.</param>
        /// <returns></returns>
        [DllImport("advapi32.dll", EntryPoint = "CredFree", SetLastError = true)]
        private static extern bool CredFree([In] IntPtr buffer);

        /// <summary>
        /// The CredDelete function deletes a credential from the user's credential set. The credential set used is the one associated with the logon session of the current token. The token must not have the user's SID disabled.
        /// </summary>
        /// <param name="targetName">Pointer to a null-terminated string that contains the name of the credential to delete.</param>
        /// <param name="type">Type of the credential to delete. Must be one of the CRED_TYPE_* defined types. For a list of the defined types, see the Type member of the CREDENTIAL structure.</param>
        /// <param name="flags">Reserved and must be zero.</param>
        /// <returns></returns>
        [DllImport("advapi32.dll", EntryPoint = "CredDelete", SetLastError = true)]
        private static extern bool CredDelete(string targetName, CredentialType type, UInt32 flags);

        private static void ThrowLastWin32Error()
        {
            Marshal.ThrowExceptionForHR(Marshal.GetHRForLastWin32Error());
        }

        #endregion

        #region Public Methods

        /// <summary>
        /// Writes a credential to the Credential Manager Password Vault
        /// </summary>
        /// <param name="credential">The credential to store</param>
        /// <param name="flags">Write flags</param>
        public static void Write(Credential credential, CredWriteFlags flags = 0x0)
        {
            CREDENTIAL NewCred = credential.ToWin32Credential();

            try
            {
                bool Success = CredWrite(ref NewCred, (UInt32)flags);

                if (!Success)
                {
                    int Err = Marshal.GetLastWin32Error();
                    ThrowLastWin32Error();
                }
            }
            finally
            {
                Marshal.FreeHGlobal(NewCred.TargetName);
                Marshal.FreeHGlobal(NewCred.CredentialBlob);
                Marshal.FreeHGlobal(NewCred.UserName);
                Marshal.FreeHGlobal(NewCred.Comment);
                Marshal.FreeHGlobal(NewCred.TargetAlias);
                Marshal.FreeHGlobal(NewCred.Attributes);
            }
        }

        /// <summary>
        /// Reads a credential from the Credential Manager Password Vault
        /// </summary>
        /// <param name="target">The credential target</param>
        /// <param name="type">The credential type</param>
        /// <returns>The stored credential object</returns>
        public static Credential Read(string target, CredentialType type = CredentialType.CRED_TYPE_GENERIC)
        {
            IntPtr CredentialPtr;
            bool Success = CredRead(target, type, 0, out CredentialPtr);

            if (Success)
            {
                CREDENTIAL cred = Marshal.PtrToStructure<CREDENTIAL>(CredentialPtr);
                Credential NewCred = Credential.FromWin32Credential(cred);
                CredFree(CredentialPtr);
                return NewCred;
            }
            else
            {
                ThrowLastWin32Error();
            }

            return null;
        }

        /// <summary>
        /// Deletes a stored credential
        /// </summary>
        /// <param name="target">The credential to delete</param>
        /// <param name="type">The type of the credential</param>
        public static void Delete(string target, CredentialType type = CredentialType.CRED_TYPE_GENERIC)
        {
            bool Success = CredDelete(target, type, 0x0);

            if (!Success)
            {
                ThrowLastWin32Error();
            }
        }

        /// <summary>
        /// Enumerates the credentials from the user's credential set. The credential set used is the one associated with the logon session of the current token. The token must not have the user's SID disabled.
        /// </summary>
        /// <param name="filter">Only credentials with a TargetName matching the filter will be returned. The filter specifies a name prefix followed by an asterisk. For instance, the filter "FRED*" will return all credentials with a TargetName beginning with the string "FRED".
        /// If NULL is specified, all credentials will be returned.</param>
        /// <returns></returns>
        public static IReadOnlyCollection<Credential> Enumerate(string filter)
        {
            return Enumerate(filter, 0x0);
        }

        /// <summary>
        /// Enumerates the credentials from the user's credential set. The credential set used is the one associated with the logon session of the current token. The token must not have the user's SID disabled.
        /// </summary>
        /// <returns></returns>
        public static IReadOnlyCollection<Credential> Enumerate()
        {
            return Enumerate(null, CredEnumerateFlags.CRED_ENUMERATE_ALL_CREDENTIALS);
        }

        #endregion

        #region Private Methods

        private static IReadOnlyCollection<Credential> Enumerate(string filter, CredEnumerateFlags flags = 0x0)
        {
            List<Credential> Results = new List<Credential>();

            UInt32 Count = 0;
            IntPtr Credentials = IntPtr.Zero;

            bool Success = CredEnumerate(filter, (UInt32)flags, out Count, out Credentials);

            if (Success)
            {
                for (int i = 0; i < Count; i++)
                {
                    IntPtr CredPtr = Marshal.ReadIntPtr(Credentials, i * Marshal.SizeOf<IntPtr>());

                    CREDENTIAL Cred = Marshal.PtrToStructure<CREDENTIAL>(CredPtr);

                    Results.Add(Credential.FromWin32Credential(Cred));
                }

                CredFree(Credentials);

                return Results;
            }
            else
            {
                ThrowLastWin32Error();
                return null;
            }
        }

        #endregion
    }
}
