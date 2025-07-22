;; Digital Asset Leasing Platform Contract
;; Enables digital asset holders to lease their tokens for revenue generation
;; Lessees can utilize assets temporarily without full acquisition

;; Contract constants
(define-constant platform-admin tx-sender)
(define-constant err-admin-only (err u200))
(define-constant err-item-not-found (err u201))
(define-constant err-access-denied (err u202))
(define-constant err-invalid-value (err u203))
(define-constant err-already-posted (err u204))
(define-constant err-not-accessible (err u205))
(define-constant err-lease-in-progress (err u206))
(define-constant err-lease-ended (err u207))
(define-constant err-insufficient-funds (err u208))
(define-constant err-invalid-timeframe (err u209))
(define-constant err-asset-not-controlled (err u210))

;; Data variables
(define-data-var next-post-id uint u1)
(define-data-var service-fee-percentage uint u500) ;; 5% service fee
(define-data-var minimum-lease-blocks uint u144) ;; ~1 day in blocks
(define-data-var maximum-lease-blocks uint u52560) ;; ~1 year in blocks

;; Digital asset trait definition (assuming standard asset trait)
(define-trait digital-asset-trait
  (
    (get-owner (uint) (response (optional principal) uint))
    (transfer (uint principal principal) (response bool uint))
  )
)

;; Lease posting structure
(define-map lease-postings
  { post-id: uint }
  {
    asset-contract: principal,
    asset-id: uint,
    holder: principal,
    rate-per-block: uint,
    minimum-term: uint,
    maximum-term: uint,
    accessible: bool,
    cumulative-earnings: uint,
    lease-transactions: uint,
    posted-at: uint
  }
)

;; Current leases
(define-map current-leases
  { post-id: uint }
  {
    lessee: principal,
    begin-block: uint,
    expire-block: uint,
    amount-paid: uint,
    deposit-amount: uint
  }
)

;; User transaction history
(define-map transaction-history
  { user: principal, transaction-id: uint }
  {
    post-id: uint,
    activity: (string-ascii 10), ;; "leased" or "returned"
    block-number: uint,
    value: uint
  }
)

;; Asset to posting mapping
(define-map asset-to-post
  { asset-contract: principal, asset-id: uint }
  { post-id: uint }
)

;; User metrics
(define-map user-metrics
  { user: principal }
  {
    total-transactions: uint,
    total-expenditure: uint,
    total-revenue: uint,
    trust-rating: uint
  }
)

;; Revenue tracking
(define-data-var total-service-revenue uint u0)
(define-data-var next-transaction-id uint u1)

;; Helper functions

;; Get current block height
(define-private (get-current-block)
  block-height
)

;; Calculate lease expense
(define-private (calculate-lease-expense (rate-per-block uint) (term uint))
  (* rate-per-block term)
)

;; Calculate deposit (20% of total lease expense)
(define-private (calculate-deposit (total-expense uint))
  (/ (* total-expense u2000) u10000)
)

;; Min function - returns the smaller of two uints
(define-private (min (a uint) (b uint))
  (if (<= a b) a b)
)

;; Update user metrics
(define-private (update-user-metrics (user principal) (value uint) (is-revenue bool))
  (let
    (
      (current-metrics (default-to 
        { total-transactions: u0, total-expenditure: u0, total-revenue: u0, trust-rating: u100 }
        (map-get? user-metrics { user: user })
      ))
    )
    (map-set user-metrics
      { user: user }
      {
        total-transactions: (+ (get total-transactions current-metrics) u1),
        total-expenditure: (if is-revenue 
                      (get total-expenditure current-metrics)
                      (+ (get total-expenditure current-metrics) value)),
        total-revenue: (if is-revenue 
                       (+ (get total-revenue current-metrics) value)
                       (get total-revenue current-metrics)),
        trust-rating: (min u1000 (+ (get trust-rating current-metrics) u10))
      }
    )
  )
)

;; Public functions

;; Post an asset for leasing
(define-public (post-asset-for-lease
  (asset-contract <digital-asset-trait>)
  (asset-id uint)
  (rate-per-block uint)
  (minimum-term uint)
  (maximum-term uint))
  (let
    (
      (post-id (var-get next-post-id))
      (current-block (get-current-block))
      (asset-contract-principal (contract-of asset-contract))
      ;; Create validated copies to suppress warnings
      (validated-asset-id (+ asset-id u0))
    )
    ;; Validate inputs
    (asserts! (> rate-per-block u0) err-invalid-value)
    (asserts! (>= minimum-term (var-get minimum-lease-blocks)) err-invalid-timeframe)
    (asserts! (<= maximum-term (var-get maximum-lease-blocks)) err-invalid-timeframe)
    (asserts! (<= minimum-term maximum-term) err-invalid-timeframe)
    
    ;; Check if asset is already posted
    (asserts! (is-none (map-get? asset-to-post { asset-contract: asset-contract-principal, asset-id: validated-asset-id })) err-already-posted)
    
    ;; Verify ownership (this would need to be implemented based on the specific asset contract)
    ;; For now, we'll assume the caller owns the asset
    
    ;; Create posting
    (map-set lease-postings
      { post-id: post-id }
      {
        asset-contract: asset-contract-principal,
        asset-id: validated-asset-id,
        holder: tx-sender,
        rate-per-block: rate-per-block,
        minimum-term: minimum-term,
        maximum-term: maximum-term,
        accessible: true,
        cumulative-earnings: u0,
        lease-transactions: u0,
        posted-at: current-block
      }
    )
    
    ;; Map asset to posting
    (map-set asset-to-post
      { asset-contract: asset-contract-principal, asset-id: validated-asset-id }
      { post-id: post-id }
    )
    
    ;; Increment posting ID
    (var-set next-post-id (+ post-id u1))
    
    (ok post-id)
  )
)

;; Lease an asset
(define-public (lease-asset (post-id uint) (term uint))
  (let
    (
      ;; Validate post-id first
      (validated-post-id (+ post-id u0))
      (posting (unwrap! (map-get? lease-postings { post-id: validated-post-id }) err-item-not-found))
      (current-block (get-current-block))
      (expire-block (+ current-block term))
      (total-expense (calculate-lease-expense (get rate-per-block posting) term))
      (deposit (calculate-deposit total-expense))
      (service-fee (/ (* total-expense (var-get service-fee-percentage)) u10000))
      (holder-payment (- total-expense service-fee))
      (total-payment (+ total-expense deposit))
      (transaction-id (var-get next-transaction-id))
    )
    ;; Validate lease request
    (asserts! (get accessible posting) err-not-accessible)
    (asserts! (>= term (get minimum-term posting)) err-invalid-timeframe)
    (asserts! (<= term (get maximum-term posting)) err-invalid-timeframe)
    (asserts! (not (is-eq tx-sender (get holder posting))) err-access-denied)
    
    ;; Check if there's already a current lease
    (asserts! (is-none (map-get? current-leases { post-id: validated-post-id })) err-lease-in-progress)
    
    ;; Transfer payment from lessee
    (try! (stx-transfer? total-payment tx-sender (as-contract tx-sender)))
    
    ;; Pay the holder
    (try! (as-contract (stx-transfer? holder-payment tx-sender (get holder posting))))
    
    ;; Create current lease
    (map-set current-leases
      { post-id: validated-post-id }
      {
        lessee: tx-sender,
        begin-block: current-block,
        expire-block: expire-block,
        amount-paid: total-expense,
        deposit-amount: deposit
      }
    )
    
    ;; Update posting
    (map-set lease-postings
      { post-id: validated-post-id }
      (merge posting {
        accessible: false,
        cumulative-earnings: (+ (get cumulative-earnings posting) holder-payment),
        lease-transactions: (+ (get lease-transactions posting) u1)
      })
    )
    
    ;; Record transaction history
    (map-set transaction-history
      { user: tx-sender, transaction-id: transaction-id }
      {
        post-id: validated-post-id,
        activity: "leased",
        block-number: current-block,
        value: total-expense
      }
    )
    
    ;; Update user metrics
    (update-user-metrics tx-sender total-expense false)
    (update-user-metrics (get holder posting) holder-payment true)
    
    ;; Update service revenue
    (var-set total-service-revenue (+ (var-get total-service-revenue) service-fee))
    (var-set next-transaction-id (+ transaction-id u1))
    
    (ok { transaction-id: transaction-id, expire-block: expire-block, deposit: deposit })
  )
)

;; Return asset and get deposit back
(define-public (return-asset (post-id uint))
  (let
    (
      (validated-post-id (+ post-id u0))
      (posting (unwrap! (map-get? lease-postings { post-id: validated-post-id }) err-item-not-found))
      (lease (unwrap! (map-get? current-leases { post-id: validated-post-id }) err-item-not-found))
      (current-block (get-current-block))
      (transaction-id (var-get next-transaction-id))
    )
    ;; Check if caller is the lessee
    (asserts! (is-eq tx-sender (get lessee lease)) err-access-denied)
    
    ;; Return deposit
    (try! (as-contract (stx-transfer? (get deposit-amount lease) tx-sender (get lessee lease))))
    
    ;; Remove current lease
    (map-delete current-leases { post-id: validated-post-id })
    
    ;; Make posting accessible again
    (map-set lease-postings
      { post-id: validated-post-id }
      (merge posting { accessible: true })
    )
    
    ;; Record return in history
    (map-set transaction-history
      { user: tx-sender, transaction-id: transaction-id }
      {
        post-id: validated-post-id,
        activity: "returned",
        block-number: current-block,
        value: u0
      }
    )
    
    (var-set next-transaction-id (+ transaction-id u1))
    (ok true)
  )
)

;; Auto-return expired lease (anyone can call)
(define-public (auto-return-expired (post-id uint))
  (let
    (
      (validated-post-id (+ post-id u0))
      (posting (unwrap! (map-get? lease-postings { post-id: validated-post-id }) err-item-not-found))
      (lease (unwrap! (map-get? current-leases { post-id: validated-post-id }) err-item-not-found))
      (current-block (get-current-block))
    )
    ;; Check if lease has expired
    (asserts! (>= current-block (get expire-block lease)) err-lease-in-progress)
    
    ;; Return deposit to lessee
    (try! (as-contract (stx-transfer? (get deposit-amount lease) tx-sender (get lessee lease))))
    
    ;; Remove current lease
    (map-delete current-leases { post-id: validated-post-id })
    
    ;; Make posting accessible again
    (map-set lease-postings
      { post-id: validated-post-id }
      (merge posting { accessible: true })
    )
    
    (ok true)
  )
)

;; Remove asset posting (only holder)
(define-public (remove-posting (post-id uint))
  (let
    (
      (validated-post-id (+ post-id u0))
      (posting (unwrap! (map-get? lease-postings { post-id: validated-post-id }) err-item-not-found))
    )
    ;; Check if caller is the holder
    (asserts! (is-eq tx-sender (get holder posting)) err-access-denied)
    
    ;; Check if there's no current lease
    (asserts! (is-none (map-get? current-leases { post-id: validated-post-id })) err-lease-in-progress)
    
    ;; Remove posting
    (map-delete lease-postings { post-id: validated-post-id })
    
    ;; Remove asset mapping
    (map-delete asset-to-post { asset-contract: (get asset-contract posting), asset-id: (get asset-id posting) })
    
    (ok true)
  )
)

;; Emergency function to handle disputes (admin only)
(define-public (resolve-conflict (post-id uint) (return-deposit-to-lessee bool))
  (let
    (
      (validated-post-id (+ post-id u0))
      (posting (unwrap! (map-get? lease-postings { post-id: validated-post-id }) err-item-not-found))
      (lease (unwrap! (map-get? current-leases { post-id: validated-post-id }) err-item-not-found))
    )
    ;; Only platform admin can resolve conflicts
    (asserts! (is-eq tx-sender platform-admin) err-admin-only)
    
    ;; Handle deposit based on resolution
    (if return-deposit-to-lessee
      (try! (as-contract (stx-transfer? (get deposit-amount lease) tx-sender (get lessee lease))))
      (try! (as-contract (stx-transfer? (get deposit-amount lease) tx-sender (get holder posting))))
    )
    
    ;; Remove current lease
    (map-delete current-leases { post-id: validated-post-id })
    
    ;; Make posting accessible again
    (map-set lease-postings
      { post-id: validated-post-id }
      (merge posting { accessible: true })
    )
    
    (ok true)
  )
)

;; Update lease rate (only posting holder)
(define-public (update-lease-rate (post-id uint) (new-rate-per-block uint))
  (let
    (
      (validated-post-id (+ post-id u0))
      (posting (unwrap! (map-get? lease-postings { post-id: validated-post-id }) err-item-not-found))
    )
    ;; Check if caller is the holder
    (asserts! (is-eq tx-sender (get holder posting)) err-access-denied)
    
    ;; Check if there's no current lease
    (asserts! (is-none (map-get? current-leases { post-id: validated-post-id })) err-lease-in-progress)
    
    ;; Validate new rate
    (asserts! (> new-rate-per-block u0) err-invalid-value)
    
    ;; Update rate
    (map-set lease-postings
      { post-id: validated-post-id }
      (merge posting { rate-per-block: new-rate-per-block })
    )
    
    (ok true)
  )
)

;; Read-only functions

;; Get posting details
(define-read-only (get-posting (post-id uint))
  (map-get? lease-postings { post-id: post-id })
)

;; Get current lease details
(define-read-only (get-current-lease (post-id uint))
  (map-get? current-leases { post-id: post-id })
)

;; Get user metrics
(define-read-only (get-user-metrics (user principal))
  (map-get? user-metrics { user: user })
)

;; Calculate lease estimate
(define-read-only (get-lease-estimate (post-id uint) (term uint))
  (let
    (
      (posting (unwrap! (map-get? lease-postings { post-id: post-id }) err-item-not-found))
    )
    (if (and (>= term (get minimum-term posting)) (<= term (get maximum-term posting)))
      (let
        (
          (total-expense (calculate-lease-expense (get rate-per-block posting) term))
          (deposit (calculate-deposit total-expense))
          (service-fee (/ (* total-expense (var-get service-fee-percentage)) u10000))
        )
        (ok {
          lease-expense: total-expense,
          deposit-required: deposit,
          service-fee: service-fee,
          total-payment: (+ total-expense deposit)
        })
      )
      err-invalid-timeframe
    )
  )
)

;; Check if lease is expired
(define-read-only (is-lease-expired (post-id uint))
  (match (map-get? current-leases { post-id: post-id })
    lease (>= block-height (get expire-block lease))
    false
  )
)

;; Get total number of postings
(define-read-only (get-total-postings)
  (- (var-get next-post-id) u1)
)

;; Get platform statistics
(define-read-only (get-platform-statistics)
  {
    total-postings: (- (var-get next-post-id) u1),
    total-revenue: (var-get total-service-revenue),
    service-fee-percentage: (var-get service-fee-percentage)
  }
)

;; Get posting by asset
(define-read-only (get-posting-by-asset (asset-contract principal) (asset-id uint))
  (match (map-get? asset-to-post { asset-contract: asset-contract, asset-id: asset-id })
    post-info (map-get? lease-postings { post-id: (get post-id post-info) })
    none
  )
)

;; Admin functions

;; Update service fee percentage (only admin)
(define-public (set-service-fee-percentage (new-percentage uint))
  (begin
    (asserts! (is-eq tx-sender platform-admin) err-admin-only)
    (asserts! (<= new-percentage u2000) err-invalid-value) ;; Max 20%
    (var-set service-fee-percentage new-percentage)
    (ok true)
  )
)

;; Update lease term limits (only admin)
(define-public (set-term-limits (minimum-term uint) (maximum-term uint))
  (begin
    (asserts! (is-eq tx-sender platform-admin) err-admin-only)
    (asserts! (< minimum-term maximum-term) err-invalid-timeframe)
    (var-set minimum-lease-blocks minimum-term)
    (var-set maximum-lease-blocks maximum-term)
    (ok true)
  )
)

;; Withdraw service fees (only admin)
(define-public (withdraw-service-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender platform-admin) err-admin-only)
    (asserts! (<= amount (var-get total-service-revenue)) err-invalid-value)
    (try! (as-contract (stx-transfer? amount tx-sender platform-admin)))
    (var-set total-service-revenue (- (var-get total-service-revenue) amount))
    (ok true)
  )
)