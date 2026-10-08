# D SecureGuard logo

`d-secureguard-logo.png` is the generated master for launcher icons and in-app
branding. Built-in imagegen was used to create a square, opaque green logo with
a white shield, capital D and mint keyhole. Its pixels were resized for platform
icon packaging; no image-generation API key is part of this project.

Final generation prompt:

> Use case: logo-brand. Create a polished standalone square mobile app logo mark for D SecureGuard, a product activation and security management app. Flat crisp geometric vector-like design: a strong white shield silhouette incorporating a bold capital D and a subtle lock/keyhole in negative space. Deep emerald green full-bleed solid background (#216B51), small mint accent optional. Single centered symbol occupying about 62% of the square with generous safe margin for circular/maskable cropping. Elegant modern trustworthy, readable at 48 pixels. Square 1024x1024 master, opaque background, no rounded outside corners (operating systems apply mask). No words, no text except the incorporated D, no mockup, no watermark, no 3D shadows, no busy gradients. Deliver only the single app logo image.

To recreate launcher sizes on Windows:

```powershell
.\scripts\Generate-AppIcons.ps1
```

The original generated master is retained in the Codex generated-images directory.
The project copies of all consumed icons are in this workspace.
