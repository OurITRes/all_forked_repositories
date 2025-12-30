# Credential Manager

## Description

Provides a wrapper around the Credential Manager Win32 API.

## Usage

Creates a new stored credential for outlook.com
    CredentialManagerFactory.Write(new Credential("john.smith", "p@ssw0rd", "outlook.com", CredentialType.CRED_TYPE_GENERIC, CredentialPersistence.CRED_PERSIST_LOCAL_MACHINE));

Retrieves the credential information for outlook.com
    Credential cred = CredentialManagerFactory.Read("outlook.com");

Retrieves all stored credentials whose target name match the filter outlook*
	IReadOnlyCollection<Credential> Creds = CredentialManagerFactory.Enumerate("outlook*");

Retrieves all stored credentials.
	IReadOnlyCollection<Credential> Creds = CredentialManagerFactory.Enumerate();

Deletes the previously created stored credentials for outlook.com
	CredentialManagerFactory.Delete("outlook.com");

When writing and reading stored credentials, if not specified, the credential type defaults to CRED_TYPE_GENERIC.