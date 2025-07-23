# KeyPath Safety Features

## 🛡️ **Multiple Layers of Protection Against Keyboard Freezing**

### **1. Safe Configuration Defaults**
- **`process-unmapped-keys no`** - Only intercepts explicitly mapped keys
- **`danger-enable-cmd yes`** - Allows system shortcuts (Cmd+Q, etc.) to work
- **Minimal key mapping** - Only maps what user specifies

### **2. Pre-Save Validation**
- **Config validation** - Every config is tested with `kanata --check` before saving
- **Syntax checking** - Invalid configs are rejected before they can cause problems
- **Error reporting** - Clear feedback if config is invalid

### **3. Emergency Controls**
- **🚨 Emergency Stop button** - Immediately stops Kanata service
- **System shortcuts work** - Cmd+Q, Cmd+Tab, etc. remain functional
- **Force restart recovery** - System can always be recovered with restart

### **4. Safe Testing Approach**
- **Foreground testing** - Test configs manually before system deployment
- **Incremental changes** - One key mapping at a time
- **Status monitoring** - Real-time service status in app

### **5. Recovery Methods**

#### **If Keyboard Freezes:**
1. **Emergency Stop** - Click 🚨 button in KeyPath app
2. **Terminal recovery** - Open Terminal and run:
   ```bash
   sudo launchctl kill TERM system/com.keypath.kanata
   ```
3. **Force restart** - Hold power button for 10 seconds

#### **Prevention Commands:**
```bash
# Test config safely first
/usr/local/bin/kanata-cmd --cfg /path/to/config.kbd --check

# Run in foreground (can Ctrl+C to stop)
/usr/local/bin/kanata-cmd --cfg /path/to/config.kbd

# Stop service
sudo launchctl kill TERM system/com.keypath.kanata
```

### **6. Safe Configuration Template**
```lisp
(defcfg
  ;; SAFETY: Only process explicitly mapped keys
  process-unmapped-keys no
  
  ;; SAFETY: Allow cmd for system shortcuts  
  danger-enable-cmd yes
)

(defsrc
  ;; Only list keys you want to remap
  caps
)

(deflayer base
  ;; Map to safe outputs
  esc
)
```

### **7. What Makes Configs Unsafe**
❌ **Dangerous settings:**
- `process-unmapped-keys yes` without full key mapping
- Mapping essential keys (like `escape`) without alternatives
- Complex macros without escape sequences

✅ **Safe practices:**
- Map only non-essential keys initially
- Test one key at a time
- Keep system shortcuts available
- Use validation before deployment

## 🎯 **Testing Protocol**
1. **Validate** config with `--check`
2. **Test manually** in foreground mode
3. **Deploy to service** only after verification
4. **Monitor status** in KeyPath app
5. **Emergency stop** if issues occur

These safety features prevent the keyboard freezing that occurred previously!