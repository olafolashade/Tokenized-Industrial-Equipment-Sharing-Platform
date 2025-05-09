;; Payment Settlement Contract
;; Handles automated compensation for equipment usage

(define-data-var contract-owner principal tx-sender)
(define-data-var platform-fee-percentage uint u5) ;; 5% platform fee

;; Payment record struct
(define-map payment-records
  { payment-id: uint }
  {
    reservation-id: uint,
    asset-id: uint,
    owner: principal,
    renter: principal,
    amount: uint,
    platform-fee: uint,
    status: (string-ascii 20), ;; "pending", "completed", "refunded"
    created-at: uint
  }
)

;; Counter for payment IDs
(define-data-var payment-id-counter uint u1)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PAYMENT-NOT-FOUND (err u101))
(define-constant ERR-INSUFFICIENT-FUNDS (err u102))
(define-constant ERR-INVALID-STATUS (err u103))
(define-constant ERR-TRANSFER-FAILED (err u104))

;; SIP-010 token trait
(define-trait ft-trait
  (
    ;; Transfer from the caller to a new principal
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
  )
)

;; Check if caller is contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner)))

;; Get the next payment ID and increment counter
(define-private (get-next-payment-id)
  (let ((current-id (var-get payment-id-counter)))
    (var-set payment-id-counter (+ current-id u1))
    current-id))

;; Calculate platform fee
(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-percentage)) u100))

;; Create a payment record
(define-public (create-payment
    (reservation-id uint)
    (asset-id uint)
    (owner principal)
    (amount uint)
    (token <ft-trait>))
  (let ((payment-id (get-next-payment-id))
        (renter tx-sender)
        (platform-fee (calculate-platform-fee amount))
        (owner-amount (- amount platform-fee))
        (block-height block-height))

    ;; Transfer tokens from renter to contract
    (asserts! (is-ok (contract-call? token transfer
                                    amount
                                    tx-sender
                                    (as-contract tx-sender)
                                    none))
              ERR-TRANSFER-FAILED)

    ;; Create payment record
    (map-set payment-records
      { payment-id: payment-id }
      {
        reservation-id: reservation-id,
        asset-id: asset-id,
        owner: owner,
        renter: renter,
        amount: amount,
        platform-fee: platform-fee,
        status: "pending",
        created-at: block-height
      })

    (ok payment-id)))

;; Complete payment (transfer to owner)
(define-public (complete-payment
    (payment-id uint)
    (token <ft-trait>))
  (let ((payment (map-get? payment-records { payment-id: payment-id })))
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (is-some payment) ERR-PAYMENT-NOT-FOUND)

    (let ((unwrapped (unwrap-panic payment))
          (owner-amount (- (get amount unwrapped) (get platform-fee unwrapped))))

      ;; Validate payment is pending
      (asserts! (is-eq (get status unwrapped) "pending") ERR-INVALID-STATUS)

      ;; Transfer owner amount
      (as-contract
        (asserts! (is-ok (contract-call? token transfer
                                        owner-amount
                                        tx-sender
                                        (get owner unwrapped)
                                        none))
                  ERR-TRANSFER-FAILED))

      ;; Update payment status
      (map-set payment-records
        { payment-id: payment-id }
        (merge unwrapped { status: "completed" }))

      (ok true))))

;; Refund payment to renter
(define-public (refund-payment
    (payment-id uint)
    (token <ft-trait>))
  (let ((payment (map-get? payment-records { payment-id: payment-id })))
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (is-some payment) ERR-PAYMENT-NOT-FOUND)

    (let ((unwrapped (unwrap-panic payment)))

      ;; Validate payment is pending
      (asserts! (is-eq (get status unwrapped) "pending") ERR-INVALID-STATUS)

      ;; Transfer full amount back to renter
      (as-contract
        (asserts! (is-ok (contract-call? token transfer
                                        (get amount unwrapped)
                                        tx-sender
                                        (get renter unwrapped)
                                        none))
                  ERR-TRANSFER-FAILED))

      ;; Update payment status
      (map-set payment-records
        { payment-id: payment-id }
        (merge unwrapped { status: "refunded" }))

      (ok true))))

;; Update platform fee percentage
(define-public (set-platform-fee (new-fee-percentage uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-fee-percentage u30) (err u105)) ;; Max 30% fee
    (ok (var-set platform-fee-percentage new-fee-percentage))))

;; Get payment record details
(define-read-only (get-payment-record (payment-id uint))
  (map-get? payment-records { payment-id: payment-id }))

;; Get current platform fee percentage
(define-read-only (get-platform-fee-percentage)
  (var-get platform-fee-percentage))

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-owner new-owner))))
