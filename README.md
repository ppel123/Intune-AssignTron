# **Intune AssignTron**

**Intune AssignTron** is an automated tool designed to simplify the management and retrieval of assignment details for various configurations within **Microsoft Intune**. Whether you're managing device configurations, compliance policies, applications, scripts, or other resources, **Intune AssignTron** provides an easy way to fetch, view, and export the assignments of these resources to groups and devices.

## **Features:**

- **Fetch Assignments for Multiple Intune Resources**: Supports configuration profiles, compliance policies, mobile applications, remediation scripts, platform scripts, macOS shell scripts, app configuration policies, and app protection policies.
  
- **Built-in Group Handling**: The tool automatically handles Intune's built-in groups like "All Devices" and "All Users", ensuring that your assignment data is complete and accurate.

- **Export to CSV**: After fetching the assignments, the results are exported into CSV files for easy review and analysis.

- **Interactive User Interface**: A simple and intuitive command-line interface that allows you to choose the specific task you want to perform, making it user-friendly for admins and IT professionals.

- **Error Handling and Reporting**: Built-in error handling ensures that you receive clear messages if a problem arises while fetching data from Microsoft Graph API.

## **Use Cases:**

- **Simplify Assignment Audits**: Quickly review all assignments for a given resource across your Intune environment.
  
- **Cleanup and Maintenance**: Identify and remove outdated or unnecessary assignments, improving your environment’s performance and security.

- **Reporting and Documentation**: Export your assignment data into CSV files to maintain records or create reports for stakeholders.

## **How It Works:**

1. **Authentication**: The tool authenticates to Microsoft Graph API using the required permissions for Intune management and group data access.
  
2. **Fetch Assignment Data**: The tool queries Microsoft Graph API to retrieve assignments for the chosen resources. It handles various types of assignments including those for devices and users.

3. **Data Export**: Once the assignment data is fetched, it is displayed on the console and can be exported to CSV files for further use.

## **Installation:**

1. Install the required modules:

   ```bash
   Install-Module Microsoft.Graph -Force -AllowClobber
2. Run the tool: Launch the script in PowerShell. Once executed, the script will prompt you with on-screen instructions to fetch assignments for the Intune resources. Follow the instructions to select the operation you want to perform.

## **Requirements**:

- **Microsoft Graph API Permissions**: Make sure you have the necessary permissions set up to read Intune configuration data and access group information. This typically includes permissions such as `Group.Read.All`, `DeviceManagementConfiguration.Read.All`, and others depending on the specific resources you're working with.

- **PowerShell**: The script is designed to run in PowerShell, so ensure that PowerShell is installed on your machine. It is compatible with both Windows and Linux environments where PowerShell is available.

## **Contributing**:

Feel free to open issues or submit pull requests if you'd like to add new features, improvements, or bug fixes. Contributions are always welcome!

   
