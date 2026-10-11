@{
  # Copy this file to mutagen-config.psd1 (same folder) and edit the values.
  # mutagen-config.psd1 holds your real addresses, so it is listed in .gitignore and must not be published.
  # %USERPROFILE% and other Windows variables are expanded for you.

  MutagenVersion = '0.18.1'
  InstallDir     = '%SystemDrive%\Tools\Mutagen'

  # One entry per server you sync with.
  Targets = @(
    @{
      Name     = 'server1'
      SshHost  = 'root@192.0.2.10'                        # what ssh connects to (user@host or an alias)
      KeyFile  = '%USERPROFILE%\.ssh\id_ed25519'
      KeyHelp  = 'Log in to the server web console, open its Shell, and paste the key as a new line in /root/.ssh/authorized_keys'
    }
    @{
      Name     = 'server2'
      SshHost  = 'server2-direct'                         # an alias defined by ConfigEntry below
      KeyFile  = '%USERPROFILE%\.ssh\server2_ed25519'
      ConfigEntry = @{ Alias = 'server2-direct'; HostName = '192.0.2.20'; User = 'pi' }
      # Optional: hand the key over through server1, which already trusts this PC.
      # Relay = @{ Via = 'root@192.0.2.10'; ViaKey = '/root/.ssh/server2_ed25519'; User = 'pi'; Host = '192.0.2.20' }
      KeyHelp  = 'Log in to server2 and append the key to ~/.ssh/authorized_keys of user pi'
    }
  )

  # One entry per sync session. Mode two-way-safe is Mutagen's default and is not a backup.
  Sessions = @(
    @{ Name = 'server1-sync'; Target = 'server1'; Mode = 'two-way-safe'
       Local  = '%USERPROFILE%\Server-Sync\server1'
       Remote = 'root@192.0.2.10:~/server-sync' }
    @{ Name = 'server2-sync'; Target = 'server2'; Mode = 'two-way-safe'
       Local  = '%USERPROFILE%\Server-Sync\server2'
       Remote = 'server2-direct:/home/pi/server-sync' }
  )
}
