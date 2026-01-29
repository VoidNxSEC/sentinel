# 🔄 Flake Configuration Guide

## 📦 Two Flake Configurations

This project provides two flake configurations:

1. **`flake.nix`** - Production (GitHub URIs)
   - Uses `github:marcosfpina/*` for all components
   - Best for: CI/CD, reproducible builds, public usage
   - Fetches from GitHub on each update

2. **`flake.development.nix`** - Local Development (Path URIs)
   - Uses `path:../component` for all components
   - Best for: Local development, testing changes before pushing
   - Uses local filesystem (instant updates)

---

## 🎯 When to Use Each

### Use `flake.nix` (GitHub URIs) when:
- ✅ Running CI/CD pipelines
- ✅ Building for production
- ✅ Sharing with other developers
- ✅ Want reproducible builds
- ✅ Testing published versions

### Use `flake.development.nix` (Local Paths) when:
- 🔧 Developing components locally
- 🔧 Testing changes before commit
- 🔧 Working on multiple repos simultaneously
- 🔧 Need instant feedback (no git push required)

---

## 🔄 Switching Between Configurations

### Method 1: Rename Files (Recommended)

```bash
# Switch to local development
mv flake.nix flake.github.nix
mv flake.development.nix flake.nix
nix develop

# Switch back to GitHub version
mv flake.nix flake.development.nix
mv flake.github.nix flake.nix
nix develop
```

### Method 2: Use `--override-input` (No file changes)

```bash
# Override specific component to use local path
nix develop --override-input neoland path:../neoland

# Override all components at once
nix develop \
  --override-input neoland path:../neoland \
  --override-input phantom path:../phantom \
  --override-input neutron path:../neutron \
  --override-input cerebro path:../cerebro \
  --override-input spectre path:../spectre \
  --override-input adr-ledger path:../adr-ledger
```

### Method 3: Git Branch Strategy

```bash
# Create a local development branch
git checkout -b local-dev

# Edit flake.nix to use local paths
sed -i 's|github:marcosfpina/|path:../|g' flake.nix

# Use this branch for development
nix develop

# Keep main branch with GitHub URIs
git checkout main
nix develop  # Uses GitHub URIs
```

---

## 🚀 GitHub URI Configuration (Current)

**File**: `flake.nix`

```nix
inputs = {
  neoland.url = "github:marcosfpina/neoland";
  phantom.url = "github:marcosfpina/phantom";
  neutron.url = "github:marcosfpina/neutron";
  cerebro.url = "github:marcosfpina/cerebro";
  spectre.url = "github:marcosfpina/spectre";
  adr-ledger.url = "github:marcosfpina/adr-ledger";
};
```

**Advantages**:
- ✅ Reproducible across machines
- ✅ Works in CI/CD without setup
- ✅ Cacheable by Nix binary cache
- ✅ Version pinned via flake.lock
- ✅ Easy to share

**Disadvantages**:
- ❌ Requires `git push` to test changes
- ❌ Slower iteration cycle
- ❌ Needs internet connection

---

## 🔧 Local Path Configuration (Alternative)

**File**: `flake.development.nix`

```nix
inputs = {
  neoland.url = "path:../neoland";
  phantom.url = "path:../phantom";
  neutron.url = "path:../neutron";
  cerebro.url = "path:../cerebro";
  spectre.url = "path:../spectre";
  adr-ledger.url = "path:../adr-ledger";
};
```

**Advantages**:
- ✅ Instant updates (no git push needed)
- ✅ Fast iteration cycle
- ✅ Works offline
- ✅ Test uncommitted changes

**Disadvantages**:
- ❌ Not reproducible on other machines
- ❌ Requires local repository structure
- ❌ Won't work in CI/CD without modification

---

## 📂 Expected Directory Structure

For local development mode to work, your directory structure should be:

```
~/arch/
├── integration-tests/    # This repository
├── neoland/
├── phantom/
├── neutron/
├── cerebro/
├── spectre/
└── adr-ledger/
```

---

## 🎯 Recommended Workflow

### For Development

```bash
# 1. Clone all repositories
cd ~/arch
git clone https://github.com/marcosfpina/integration-tests
git clone https://github.com/marcosfpina/neoland
git clone https://github.com/marcosfpina/phantom
# ... etc

# 2. Switch to local development mode
cd integration-tests
mv flake.nix flake.github.nix
mv flake.development.nix flake.nix

# 3. Develop with instant feedback
nix develop
# Edit ../neoland/src/...
# Changes reflect immediately!

# 4. Before committing, test with GitHub URIs
mv flake.nix flake.development.nix
mv flake.github.nix flake.nix
nix flake update  # Update to latest GitHub versions
nix develop  # Test with published versions
```

### For CI/CD

```yaml
# GitHub Actions
- name: Run integration tests
  run: |
    # Always uses flake.nix (GitHub URIs)
    nix run .#test
```

### For Public Usage

```bash
# Users can directly use GitHub version
nix develop github:marcosfpina/integration-tests

# Or clone and use
git clone https://github.com/marcosfpina/integration-tests
cd integration-tests
nix develop  # Uses GitHub URIs by default
```

---

## 🔍 Verification

### Check Current Configuration

```bash
# Show which inputs are being used
nix flake metadata

# Show detailed input sources
nix flake metadata --json | jq '.locks.nodes'

# Check if using local or GitHub
grep -E "url.*github:|path:" flake.nix
```

### Test Both Configurations

```bash
# Test GitHub version
nix develop --override-input neoland github:marcosfpina/neoland
pytest --version

# Test local version
nix develop --override-input neoland path:../neoland
pytest --version
```

---

## 📊 Comparison Table

| Feature | GitHub URIs | Local Paths |
|---------|-------------|-------------|
| **Reproducibility** | ✅ Perfect | ❌ Machine-dependent |
| **Iteration Speed** | ❌ Slow (needs push) | ✅ Instant |
| **CI/CD Ready** | ✅ Yes | ❌ Requires setup |
| **Offline Work** | ❌ Needs internet | ✅ Fully offline |
| **Share with Team** | ✅ Easy | ❌ Complex |
| **Binary Cache** | ✅ Cacheable | ❌ Not cacheable |
| **Version Control** | ✅ Via flake.lock | ❌ Manual |

---

## 💡 Pro Tips

1. **Keep Both Versions in Sync**
   ```bash
   # Use a script to ensure both flakes have same outputs
   diff -u flake.nix flake.development.nix
   ```

2. **Use Git Ignore for Local Flake**
   ```bash
   # Add to .gitignore if you don't want to commit local version
   flake.development.nix
   ```

3. **Automate Switching with Scripts**
   ```bash
   # Create helpers
   echo 'alias nix-local="mv flake.nix flake.github.nix && mv flake.development.nix flake.nix"' >> ~/.bashrc
   echo 'alias nix-github="mv flake.nix flake.development.nix && mv flake.github.nix flake.nix"' >> ~/.bashrc
   ```

4. **Use Direnv with Conditional Loading**
   ```bash
   # .envrc
   if [ -f flake.development.nix ]; then
     echo "Using local development flake"
   fi
   use flake
   ```

---

## 🎯 Best Practices

1. ✅ **Default to GitHub URIs** (in `flake.nix`)
2. ✅ **Keep local version private** (don't commit to public repo)
3. ✅ **Document structure** in README
4. ✅ **Test both versions** before release
5. ✅ **Update flake.lock regularly**

---

<div align="center">

**Current Configuration**: 🌐 **GitHub URIs** (Production)

To switch to local development: See "Method 1" above

</div>
