# Maximo Application Suite (MAS) Keycloak Identity Toolkit

This toolkit provides a self-hostable, repeatable, and automated development/testing environment for integrating IBM Maximo Application Suite (MAS) with Keycloak as the Identity Provider (IdP) using SAML. It streamlines the setup of SAML authentication, enabling users to quickly establish a secure and functional identity management environment for testing purposes.

## 1. Project Goal

To provide a containerized, automated toolkit for setting up Keycloak as an Identity Provider (IdP) for testing SAML authentication with IBM Maximo Application Suite (MAS).

## 2. Core Components

- **Keycloak:** Open-source Identity and Access Management solution acting as the central IdP.
- **PostgreSQL:** Database for Keycloak.
- **Automation Scripts:** Shell scripts (`setup.sh`, `start.sh`, `stop.sh`, `reset.sh`, `healthcheck.sh`, `portable_timeout.sh`, `wait_for_service.sh`) to automate deployment, configuration, and management.
- **mkcert:** For generating locally trusted TLS certificates for Keycloak HTTPS.
- **OpenLDAP (Optional):** A containerized LDAP server for simulating an enterprise directory and testing LDAP federation.

## 3. Prerequisites

Before you begin, ensure you have the following installed on your system:

- **Podman:** A daemonless container engine for developing, managing, and running OCI Containers. Installation instructions can be found at [https://podman.io/docs/installation](https://podman.io/docs/installation).
  - **macOS:** You can install Podman via Homebrew: `brew install podman`
- **mkcert:** A utility for creating locally trusted TLS certificates.
  - **macOS:** Install via Homebrew: `brew install mkcert nss`
  - **Linux:** Follow instructions at [https://github.com/FiloSottile/mkcert](https://github.com/FiloSottile/mkcert)
  - **Important:** After installing mkcert, you **must** install its local Certificate Authority (CA) by running `mkcert -install`. You might need to restart your browser afterward for the CA to be trusted.
- **Docker Compose:** This toolkit uses `podman-compose` to manage containers. Ensure it's installed and configured to work with Podman.

## 4. Installation and Setup Process

Follow these steps to set up the toolkit:

### Step 1: Clone the Repository

First, clone this project's repository to your local machine:

```bash
git clone <repository_url>
cd <repository_directory>
```

### Step 2: Configure Environment Variables

1.  Copy the example environment file:
    ```bash
    cp .env.example .env
    ```
2.  Edit the `.env` file and fill in your specific secrets and configurations:

    - `PG_PASSWORD`: The password for the PostgreSQL database used by Keycloak.
    - `KEYCLOAK_ADMIN_PASSWORD`: The password for the initial Keycloak administrator user.
    - `KEYCLOAK_ADMIN_USERNAME`: The username for the initial Keycloak administrator user (defaults to `admin`).
    - `KEYCLOAK_HOSTNAME_URL`: The **exact URL** you will use to access Keycloak from your browser (e.g., `https://localhost:8443`). This is critical for Keycloak to generate correct metadata and handle redirects.
    - `KEYCLOAK_HOSTNAME`: The hostname part of your `KEYCLOAK_HOSTNAME_URL` (e.g., `localhost`).
    - `LDAP_ADMIN_PASSWORD`: The password for the OpenLDAP administrator. **CHANGE THIS FROM THE DEFAULT!**
    - `LDAP_REPL_PASSWORD`: The replication password for OpenLDAP (if applicable). **CHANGE THIS FROM THE DEFAULT!**

    **Example `.env`:**

    ```env
    PG_PASSWORD=mysecretpassword123
    KEYCLOAK_ADMIN_PASSWORD=mysecurekeycloakadminpassword
    KEYCLOAK_ADMIN_USERNAME=admin
    KEYCLOAK_HOSTNAME_URL=https://localhost:8443
    KEYCLOAK_HOSTNAME=localhost
    LDAP_ADMIN_PASSWORD=supersecretldapadminpass
    LDAP_REPL_PASSWORD=supersecretldapreplpass
    ```

### Step 3: Prepare OpenLDAP Data (Optional)

If you plan to use LDAP federation, prepare your initial LDAP data.

1.  **Create LDIF Directory:**
    ```bash
    mkdir -p OpenLDAP/ldap-init
    ```
2.  **Create LDIF File:** Create an LDIF file (e.g., `OpenLDAP/ldap-init/init.ldif`) with your desired base DN, admin user, and dummy users. Refer to the example LDIF content provided in the project's documentation or contributing guide.
    - **Crucially:** Ensure the `LDAP_ADMIN_PASSWORD` in your `.env` file matches the password set for the LDAP admin user in your `init.ldif` file. The `osixia/openldap` image may hash plain text passwords upon first import, or you may need to generate SSHA hashes beforehand using `slappasswd`.

### Step 4: Run the Setup Script

This is the main setup script that orchestrates the deployment and initial configuration.

1.  Run the setup script from the **project's root directory**:
    ```bash
    ./Scripts/setup.sh
    ```
2.  **Follow Script Prompts:** The script will:
    - Perform prerequisite checks (Podman, mkcert).
    - Load your `.env` variables.
    - Source helper functions.
    - Generate TLS certificates if they don't exist.
    - Start Keycloak, PostgreSQL, and OpenLDAP containers using `docker-compose`.
    - Wait for Keycloak to become ready using polling.
    - Import the base Keycloak realm from `./Keycloak/realms/maximo-realm.json`.
    - Provide instructions for the crucial **manual configuration steps** required in Keycloak and MAS.

### Step 5: Manual Configuration (Keycloak and MAS)

After `setup.sh` completes, you must perform these manual steps to finalize the SAML integration.

#### 5.1. Configure Keycloak Client and Mappers

1.  **Access Keycloak Admin Console:** Open your browser and navigate to the `KEYCLOAK_HOSTNAME_URL` you set in your `.env` file (e.g., `https://localhost:8443`). Log in using the admin credentials (`KEYCLOAK_ADMIN_USERNAME`, `KEYCLOAK_ADMIN_PASSWORD`) you configured.

2.  **Obtain MAS SAML SP Metadata:**

    - Log in to your MAS Administration console.
    - Navigate to **Configurations > SAML Authentication**.
    - Enter a Service Provider Name (e.g., `mas-saml-sp`).
    - Select the desired **User Identifier (Name ID) format** (this should match your Keycloak configuration later).
    - Click **Generate file** and then **Download file**. Save this MAS SP metadata XML file.

3.  **Create/Import MAS SAML Client in Keycloak:**

    - In the Keycloak Admin Console, select your realm (e.g., `mytestrealm` if defined in `maximo-realm.json`, or `master`).
    - Go to **Clients**.
    - Click **Create Client**.
    - Click the **Import** button.
    - Click **Browse** and upload the MAS SP metadata XML file you downloaded.
    - Review the pre-filled settings (Client ID, Assertion Consumer Service URL (ACS), NameID format). Ensure they match your MAS configuration.
    - Click **Save**.

4.  **Configure SAML Mappers in Keycloak:**
    - Navigate to **Clients** in Keycloak and select the MAS client you just created.
    - Go to the **Mappers** tab.
    - Click **Add mapper** > **Import**.
    - Import the SAML mapper JSON files located in your `./Keycloak/mappers/` directory. These typically include mappers for `email`, `givenName` (for first name), `sn` (for last name), and `groups`.
    - **Crucially:** Refer to MAS SAML documentation for the exact SAML attribute names and formats MAS expects. Ensure your imported mappers correctly send these attributes.

#### 5.2. Configure Keycloak for LDAP Federation (Optional)

If you set up OpenLDAP and want to test federation:

1.  **Access Keycloak Admin Console:** Log in to Keycloak.
2.  **Navigate to User Federation:** In your realm, go to **User Federation** > **Add provider**.
3.  **Select LDAP:** Choose **LDAP** as the provider type.
4.  **Configure LDAP Connection:**
    - **Provider Type:** `user-ldap`
    - **Connection URL:** `ldap://openldap:389` (or `ldaps://openldap:636` if you configure TLS)
    - **Bind DN:** `cn=admin,dc=example,dc=com` (or as defined in your `docker-compose.yml` and LDIF)
    - **Bind Credential:** Enter the LDAP admin password (from your `.env` file's `LDAP_ADMIN_PASSWORD`).
    - **Search Base DN:** `dc=example,dc=com` (or as defined in your `docker-compose.yml` and LDIF)
    - **User DN for importing:** You can use the admin DN here if needed for initial sync.
    - **Test connection:** Use the "Test connection" button to verify Keycloak can connect to OpenLDAP.
5.  **Configure LDAP Mappers:**
    - After the connection is successful, configure **Mappers**. This is crucial for translating LDAP attributes to Keycloak user properties.
    - **Common Mappers to Add:**
      - Username LDAP Attribute: `uid`
      - RDNA DN User LDAP Attribute: `dn`
      - User LDAP Edit Mode: `READ_ONLY` (or `WRITABLE` if Keycloak should provision users to LDAP). For MAS testing, `READ_ONLY` is often sufficient.
      - Email Attribute: `mail`
      - First Name Attribute: `givenName`
      - Last Name Attribute: `sn`
      - Groups LDAP Filter: If you want to sync groups.
      - User Group Mappers: Map LDAP groups to Keycloak roles or groups.
6.  **Save and Test:** Save the LDAP provider configuration. Keycloak may perform an initial synchronization. Then, try logging into MAS via SAML using a user that exists _only_ in your OpenLDAP directory.

#### 6.3. Configure MAS SAML Settings

1.  **Create a Test User in Keycloak:**

    - In Keycloak Admin Console > **Users**, click **Create user**.
    - **Default Demo User:** If you have defined a default user in your `maximo-realm.json` (e.g., username `masdemo` with password `demo_password_123`), it will be created automatically upon realm import.
    - **Manual Creation:** You can also create additional users manually. Set username, email, and password. Verify the user's email if necessary.

2.  **Obtain Keycloak IdP Metadata:**

    - In Keycloak Admin Console, go to **Realm Settings**.
    - Find the **SAML 2.0 Identity Provider Metadata** link.
    - **Download the XML file** or copy the metadata URL.

3.  **Configure MAS:**
    - Log into your MAS administrative interface.
    - Navigate to the SAML configuration section.
    - Upload the Keycloak IdP metadata XML file you just downloaded, or provide the metadata URL.
    - **Crucially, configure the attribute mappings in MAS.** Ensure they align with the SAML attributes you've configured in Keycloak (e.g., map Keycloak's `email` SAML attribute to MAS's User ID/Email field, `givenName` to First Name, etc.).

## 5. Running the Environment

- **Start:** To start Keycloak, PostgreSQL, and OpenLDAP after setup:
  ```bash
  ./start.sh
  ```
- **Stop:** To stop the services without removing data:
  ```bash
  ./stop.sh
  ```
- **Reset:** To stop services, remove containers, and clear all data (database, Keycloak realm, LDAP data, certificates):
  ```bash
  ./reset.sh
  ```
  _(Note: Run `./setup.sh` again after a reset.)_

## 6. Testing SAML SSO

Once all configuration steps are complete:

1.  Attempt to access a MAS resource that requires authentication.
2.  You should be redirected to the Keycloak login page.
3.  Log in with a user created in Keycloak (either the demo user from your realm import or one you created manually). If you configured LDAP federation, try logging in with a user from your OpenLDAP directory.
4.  Upon successful authentication, you should be redirected back to MAS, logged in.
5.  Verify that your user attributes (name, email, groups) are correctly populated in MAS.
6.  Test the logout functionality to ensure Single Logout (SLO) is working.
