//! ADR-046 phase 4: the engine admits a peer only if its running code satisfies
//! this process's own designated requirement.
//!
//! The session worker and the app that launches it are the same signed
//! executable, so "the peer satisfies my designated requirement" holds for the
//! real app whatever identity signed it (Developer ID, Apple Development, or a
//! local ad-hoc build, whose requirement is its code hash). Code injected into
//! the app, or a different program holding the right PID, fails it.

use core_foundation::base::{CFType, TCFType};
use core_foundation::data::CFData;
use core_foundation::dictionary::CFDictionary;
use core_foundation::string::{CFString, CFStringRef};
use std::ffi::c_void;

type OSStatus = i32;
type SecCodeRef = *const c_void;
type SecRequirementRef = *const c_void;
const K_SEC_CS_DEFAULT_FLAGS: u32 = 0;

#[link(name = "Security", kind = "framework")]
unsafe extern "C" {
    static kSecGuestAttributeAudit: CFStringRef;
    fn SecCodeCopySelf(flags: u32, code: *mut SecCodeRef) -> OSStatus;
    fn SecCodeCopyDesignatedRequirement(
        code: SecCodeRef,
        flags: u32,
        requirement: *mut SecRequirementRef,
    ) -> OSStatus;
    fn SecRequirementCopyString(
        requirement: SecRequirementRef,
        flags: u32,
        text: *mut CFStringRef,
    ) -> OSStatus;
    fn SecRequirementCreateWithString(
        text: CFStringRef,
        flags: u32,
        requirement: *mut SecRequirementRef,
    ) -> OSStatus;
    fn SecCodeCopyGuestWithAttributes(
        host: SecCodeRef,
        attributes: *const c_void,
        flags: u32,
        guest: *mut SecCodeRef,
    ) -> OSStatus;
    fn SecCodeCheckValidity(
        code: SecCodeRef,
        flags: u32,
        requirement: SecRequirementRef,
    ) -> OSStatus;
}

unsafe extern "C" {
    fn CFRelease(object: *const c_void);
}

/// Releases a CF object when dropped.
struct Owned(*const c_void);
impl Drop for Owned {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe { CFRelease(self.0) }
        }
    }
}

/// This process's designated requirement, as text.
pub fn own_designated_requirement() -> Result<String, String> {
    unsafe {
        let mut code: SecCodeRef = std::ptr::null();
        let status = SecCodeCopySelf(K_SEC_CS_DEFAULT_FLAGS, &mut code);
        let code = Owned(code);
        if status != 0 {
            return Err(format!("SecCodeCopySelf failed ({status})"));
        }
        let mut requirement: SecRequirementRef = std::ptr::null();
        let status =
            SecCodeCopyDesignatedRequirement(code.0, K_SEC_CS_DEFAULT_FLAGS, &mut requirement);
        let requirement = Owned(requirement);
        if status != 0 {
            return Err(format!(
                "this process has no designated requirement ({status}); is it signed?"
            ));
        }
        let mut text: CFStringRef = std::ptr::null();
        let status = SecRequirementCopyString(requirement.0, K_SEC_CS_DEFAULT_FLAGS, &mut text);
        if status != 0 || text.is_null() {
            return Err(format!("SecRequirementCopyString failed ({status})"));
        }
        Ok(CFString::wrap_under_create_rule(text).to_string())
    }
}

/// Checks that the process named by `audit_token` runs valid code that
/// satisfies `requirement`.
pub fn check_peer(audit_token: &[u32; 8], requirement: &str) -> Result<(), String> {
    unsafe {
        let mut parsed: SecRequirementRef = std::ptr::null();
        let status = SecRequirementCreateWithString(
            CFString::new(requirement).as_concrete_TypeRef(),
            K_SEC_CS_DEFAULT_FLAGS,
            &mut parsed,
        );
        let parsed = Owned(parsed);
        if status != 0 {
            return Err(format!("invalid code requirement ({status})"));
        }
        let token_bytes: Vec<u8> = audit_token
            .iter()
            .flat_map(|word| word.to_ne_bytes())
            .collect();
        let key = CFString::wrap_under_get_rule(kSecGuestAttributeAudit);
        let attributes = CFDictionary::<CFString, CFType>::from_CFType_pairs(&[(
            key,
            CFData::from_buffer(&token_bytes).as_CFType(),
        )]);
        let mut guest: SecCodeRef = std::ptr::null();
        let status = SecCodeCopyGuestWithAttributes(
            std::ptr::null(),
            attributes.as_concrete_TypeRef().cast(),
            K_SEC_CS_DEFAULT_FLAGS,
            &mut guest,
        );
        let guest = Owned(guest);
        if status != 0 {
            return Err(format!("peer code not found ({status})"));
        }
        match SecCodeCheckValidity(guest.0, K_SEC_CS_DEFAULT_FLAGS, parsed.0) {
            0 => Ok(()),
            status => Err(format!(
                "peer code does not satisfy this app's signature ({status})"
            )),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn this_process_token() -> [u32; 8] {
        let (a, _b) = std::os::unix::net::UnixStream::pair().unwrap();
        kanata_state_machine::tcp_server::read_peer_identity(&a)
            .unwrap()
            .audit_token
    }

    #[test]
    fn this_process_satisfies_its_own_requirement() {
        let requirement = own_designated_requirement().expect("test binary is linker-signed");
        check_peer(&this_process_token(), &requirement).expect("admitted");
    }

    #[test]
    fn a_requirement_for_other_code_is_refused() {
        let other = r#"identifier "com.example.not-keypath" and anchor apple generic"#;
        assert!(check_peer(&this_process_token(), other).is_err());
    }

    #[test]
    fn a_token_for_no_process_is_refused() {
        let requirement = own_designated_requirement().unwrap();
        let mut token = this_process_token();
        token[5] = 999_999; // a PID that is not running
        assert!(check_peer(&token, &requirement).is_err());
    }
}
