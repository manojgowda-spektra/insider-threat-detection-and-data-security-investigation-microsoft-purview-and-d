Insider Threat Detection and Data Security Investigation: Microsoft Purview and Defender XDR Integration

Lab Overview
• Cloud: Azure
• Duration: 300 minutes
• Challenges: 5 (Configure Insider Risk Management with HR connector data, Onboard the VM, generate activity, and enable alert sharing, Hunt the generated activity with Advanced Hunting, Conduct and export a Microsoft Purview Data Security Investigation or eDiscovery fallback, Export Defender alert evidence with Python and Microsoft Graph)
• Validations: 5
• Deployed services: Windows Virtual Machine, Virtual Network, Subnet, Network Security Group, Network Interface, Public IP address with DNS/FQDN output, Custom Script Extension, VM-local lab files, best-effort Microsoft Entra app registration for Microsoft Graph Security alert export
• Scenario: Zava Manufacturing suspects a departing design engineer is taking proprietary design files before leaving the company. The learner uses the existing lab admin identity to configure Microsoft Purview Insider Risk Management with HR connector data, onboard the Azure lab VM to Microsoft Defender for Endpoint, generate controlled endpoint and email evidence, hunt the evidence in Microsoft Defender XDR Advanced Hunting, conduct and export Microsoft Purview Data Security Investigation or eDiscovery evidence, and export Microsoft Defender for Endpoint alert data through Microsoft Graph. Microsoft Learn-aligned service facts reflected in this package include Microsoft Purview Insider Risk Management, Microsoft Defender XDR Advanced Hunting tables such as DeviceFileEvents, DeviceEvents, EmailEvents, AlertInfo, and AlertEvidence, Microsoft Defender for Endpoint onboarding and EICAR test detection, Microsoft Purview eDiscovery export fallback, Microsoft Entra app registration, and Microsoft Graph /security/alerts_v2 access using SecurityAlert.Read.All.

This Package Includes

Deliverables Included in the Package
• Lab Guide
• Master Document
• Inline Validations
• Solution Guide (solution-guide/solution.md)
• Specification (Spec.md)
• ARM template, parameters and Custom Script Extension bootstrap (DeploymentPackage/)
• Azure custom RBAC role (permissions/CustomRBAC/custom-rbac-role.json)
• Custom ARM policy (permissions/CustomARMPolicy/azure-policy.json)

Inline Validations
Pre-configured inline validations enabled
• Validations/01-task-vm-readiness-and-lab-assets.ps1
• Validations/02-task-defender-onboarding-telemetry-alert-and-alert-sharing.ps1
• Validations/03-task-advanced-hunting-evidence.ps1
• Validations/04-task-dsi-exported-evidence.ps1
• Validations/05-task-graph-export-artifacts-and-alert-content.ps1

Lab Guide Preview
Preview link for the lab guide documentation:
CloudLabs generates this link once the template exists; it takes the form `https://experience.cloudlabs.ai/#labguidepreview/<lab-guide-id>/1`, where the id is copied from the Admin Center preview URL. The guide source itself is at `https://raw.githubusercontent.com/manojgowda-spektra/insider-threat-detection-and-data-security-investigation-microsoft-purview-and-d/main/LabGuidePackage/Lab%20Guide/masterdoc.json`.

Lab Environment Setup & Deployment
Lab provisioning and setup include one or more of the following components:
• ARM template deployment
• Custom Script Extension (CSE)
• Custom image-based environment setup
• Supporting deployment configurations as required

Deployment Boundary Notes
• No Microsoft.DevTestLab/schedules auto-shutdown resource is deployed; CloudLabs lab-lifetime controls govern environment shutdown and cleanup.
• Graph client values are never emitted as ARM placeholders or ARM outputs. Real Microsoft Graph client ID and secret values are written only to VM-local files such as C:\LabFiles\config.json and C:\LabFiles\GraphBootstrapStatus.json when best-effort bootstrap or the Challenge 5 manual setup succeeds.

Exclusions
This package does not include:
• Scoring or grading mechanisms for inline validations
• Complex or advanced inline question types
