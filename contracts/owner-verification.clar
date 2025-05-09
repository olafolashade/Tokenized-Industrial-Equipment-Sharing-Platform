;; Owner Verification Contract
;; Validates equipment holders and their ownership rights

(define-data-var contract-owner principal tx-sender)

;; Map to store verified equipment owners
(define-map verified-owners principal bool)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-VERIFIED (err u101))
(define-constant ERR-NOT-VERIFIED (err u102))

;; Check if caller is contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner)))

;; Verify an equipment owner
(define-public (verify-owner (owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? verified-owners owner)) ERR-ALREADY-VERIFIED)
    (ok (map-set verified-owners owner true))))

;; Revoke verification of an owner
(define-public (revoke-verification (owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? verified-owners owner)) ERR-NOT-VERIFIED)
    (ok (map-delete verified-owners owner))))

;; Check if an owner is verified
(define-read-only (is-verified-owner (owner principal))
  (default-to false (map-get? verified-owners owner)))

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-owner new-owner))))
