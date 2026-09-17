FLAPPY BIRD - WORKING SNAPSHOT v1
==================================
Erstellt: 28. Juli 2026

Das ist der bestätigt funktionierende Stand:
- Bootet direkt in Flappy Bird (keine Demo-Screens)
- SW2 startet nach Game Over neu (in-place, kein Screen-Reload)
- Spielfigur ist das Microchip-Logo (RGB565, runde Ecken)
- SRAM auf 2MB erhöht (app.overlay) wegen lv_image-Widget


WIEDERHERSTELLEN - DREI WEGE
============================

Weg 1: Fertiges Payload direkt flashen (schnellster Weg)
--------------------------------------------------------
payload.bin ist das fertige HSS-Image. SD-Karte in den Windows-Kartenleser,
dann in einer PowerShell ALS ADMINISTRATOR:

  Copy-Item "C:\developers\Zephyr_HelloFPGA\snapshots\flappy-working-v1\payload.bin" "C:\developers\Zephyr_HelloFPGA\payload.bin" -Force
  Set-ExecutionPolicy Bypass -Scope Process -Force
  "YES" | & "C:\developers\Zephyr_HelloFPGA\flash_sdcard.ps1"

Danach SD-Karte ins PIC64GX-Board, einschalten. Fertig.


Weg 2: Git-Branch/Tag im Repo auschecken (wenn Quellcode gebraucht wird)
-----------------------------------------------------------------------
Das Repo liegt in WSL unter ~/zephyr_git/pic64gx-zephyr.
Der Stand ist als Branch UND Tag gespeichert: "flappy-working-v1"

  wsl
  cd ~/zephyr_git/pic64gx-zephyr
  git checkout flappy-working-v1

Dann neu bauen mit dem Standard-Buildscript:
  bash /mnt/c/developers/Zephyr_HelloFPGA/build_demo.sh


Weg 3: Patch auf sauberes main anwenden (wenn Git-Historie verloren geht)
-------------------------------------------------------------------------
flappy-working-v1.patch enthält alle Änderungen gegen den originalen
Bitbucket-Stand (Commit c23f035).

  wsl
  cd ~/zephyr_git/pic64gx-zephyr
  git checkout main
  git am < /mnt/c/developers/Zephyr_HelloFPGA/snapshots/flappy-working-v1/flappy-working-v1.patch


DATEIEN IN DIESEM ORDNER
========================
payload.bin              Fertiges HSS-Boot-Image (an SD-Sektor 139264 flashen)
zephyr.elf               Kompiliertes Zephyr-Binary (Debug/Referenz)
flappy-working-v1.patch  Git-Patch mit allen Änderungen gegen main
README.txt               Diese Datei


WICHTIGE DETAILS
================
- SD-Karten-Offset: Sektor 139264 (= Partition p2 "primary", HSS-Payload)
  NICHT Sektor 8192 (das ist p1, U-Boot) und NICHT 2081.
- Board-Target: pic64gx_curiosity_kit/pic64gx1000/u54/smp
- Steuerung: SW2 = Springen/Start/Neustart, SW1+SW2 = (im modifizierten
  Stand nicht mehr aktiv, Neustart läuft über SW2 nach Game Over)
