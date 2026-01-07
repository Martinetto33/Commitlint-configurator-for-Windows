# Commitlint configurator for Windows
A Powershell script to allow commitlint configuration for conventional commits in Windows environments.

## Usage
Clone the repository with 

```
git clone https://github.com/Martinetto33/Commitlint-configurator-for-Windows.git
```

If you're using PowerShell, you may need to set the Execution Policy to Unrestricted for your current Process (if you don't want to enable this globally) in order to allow your session to execute the script with:

```powerhsell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted
```
> Tip: you can use `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted` to enable all future shells to execute ps1 scripts.

Enter the folder you cloned, then run:

```powershell
.\commitlint-setup.ps1
```

You'll be prompted to specify the folder you want to create the .githooks folder and the whole setup in.
The script will also install the following dependencies (if not already present):
* Scoop (a package manager for Windows)
* Node.js (for commitlint package)
* The commitlint package itself.

Then, from any IDE or shell you run git from, the hook will be triggered before any commit is accepted, enforcing usage of conventional commits.
