# Maximo IAM Toolkit

The **Maximo IAM Toolkit** provides a self-hostable, repeatable, and automated environment for integrating **IBM Maximo Application Suite (MAS)** with **Keycloak** as the central Identity Provider (IdP).

It supports **SAML**, **LDAP federation**, and is being prepared for **SCIM 2.0 provisioning** (via Keycloak extension). This toolkit is designed for development, testing, and proof-of-concept deployments of identity and access management with MAS.

---

## 1. Project Goal

To provide a **containerized, automated toolkit** for setting up Keycloak as an IdP for MAS, enabling testing and validation of:

- **SAML authentication** between MAS and Keycloak
- **LDAP federation** for enterprise directory integration
- **SCIM 2.0 provisioning** (planned, requires Keycloak 26+)

---

## 2. Core Components

- **Keycloak (v26+):** Open-source IAM solution acting as the IdP.
- **PostgreSQL:** Database backend for Keycloak.
- **OpenLDAP (Optional):** Containerized LDAP server for simulating enterprise directories.
- **Automation Scripts:** Shell scripts (`setup.sh`, `start.sh`, `stop.sh`, `reset.sh`, `healthcheck.sh`, etc.) for deployment and lifecycle management.
- **mkcert:** For generating locally trusted TLS certificates.
- **Docker/Podman Compose:** Container orchestration for local and cluster testing.

---

## 3. Current Capabilities

✅ Deploy Keycloak + Postgres in containers  
✅ Secure Keycloak with locally trusted TLS certificates  
✅ Import a preconfigured Keycloak realm for MAS testing  
✅ Configure MAS as a SAML Service Provider (SP)  
✅ Support LDAP federation (via OpenLDAP)  
✅ Automate setup and teardown with scripts

🔜 Planned:

- Add **SCIM 2.0 support** via Keycloak SCIM extension (requires Keycloak 26+)
- Helm chart / Operator packaging for OpenShift deployment
- GitOps-ready manifests for Red Hat MAS clusters

---

## 4. Prerequisites

- **Podman** or **Docker**
- **podman-compose** or **docker-compose**
- **mkcert** (for TLS certificates)
- **Git** (to clone and manage repo)

---

## 5. Setup Instructions

### Step 1: Clone the Repository

```bash
git clone git@github.com:lfdev28/Maximo_IAM_Tool.git
cd Maximo_IAM_Tool
```

### Step 2: Configure Environment

```bash
cp .env.example .env
```

Edit `.env` with your secrets and hostnames (Keycloak admin, DB password, LDAP admin, etc.).

### Step 3: Run Setup

```bash
./Scripts/setup.sh
```

This will:

- Generate TLS certs
- Start Keycloak, Postgres, and optional OpenLDAP
- Import the base Keycloak realm for MAS

### Step 4: Manual MAS Integration

- Import MAS SAML SP metadata into Keycloak
- Configure Keycloak IdP metadata in MAS
- Map attributes (email, first name, last name, groups)

---

## 6. Usage

- **Start services**
  ```bash
  ./start.sh
  ```
- **Stop services**
  ```bash
  ./stop.sh
  ```
- **Reset environment** (clear DB, LDAP, certs)
  ```bash
  ./reset.sh
  ```

---

## 7. Testing

- Log into MAS → redirected to Keycloak login
- Authenticate with Keycloak or LDAP user
- Verify attributes flow correctly into MAS
- Test logout and SAML SLO

---

## 8. Roadmap

- [ ] Add SCIM 2.0 provisioning support
- [ ] Package as Helm chart for OpenShift
- [ ] Publish as Operator for Red Hat Marketplace
- [ ] Expand LDAP federation examples
