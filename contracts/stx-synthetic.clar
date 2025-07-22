;; synthetic-assets-v2.clar
;; STX-backed synthetic asset minter with collateral management, liquidation, and fees
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Token Trait
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-trait token-trait
  (
    (mint (principal uint) (response bool uint))
    (burn (principal uint) (response bool uint))
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Constants & Errors
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-constant ERR_NOT_OWNER (err u100))
(define-constant ERR_NOT_ORACLE (err u101))
(define-constant ERR_ASSET_EXISTS (err u102))
(define-constant ERR_ASSET_NOT_FOUND (err u103))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u104))
(define-constant ERR_INSUFFICIENT_BALANCE (err u105))
(define-constant ERR_INVALID_AMOUNT (err u106))
(define-constant ERR_PRICE_NOT_SET (err u107))
(define-constant ERR_PAUSED (err u108))
(define-constant ERR_NOT_UNDERCOLLATERALIZED (err u109))
(define-constant ERR_TOKEN_CONTRACT_NOT_SET (err u110))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Storage Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-data-var owner principal tx-sender)
(define-data-var oracle principal tx-sender)
(define-data-var paused bool false)
(define-data-var treasury uint u0)
(define-data-var fee-bps uint u50) ;; 0.50%

(define-map synthetic-assets
  { symbol: (string-ascii 8) }
  { collateral-ratio: uint, price: uint, collateral-pool: uint }
)

(define-map user-minted
  { user: principal, symbol: (string-ascii 8) }
  { amount: uint, collateral: uint }
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Private Helpers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-private (get-required-collateral (amount uint) (price uint) (ratio uint))
  (/ (* (* amount price) ratio) (* u10000 u1000000))
)

(define-private (charge-fee (collateral uint))
  (let ((fee (/ (* collateral (var-get fee-bps)) u10000)))
    (var-set treasury (+ (var-get treasury) fee))
    (- collateral fee)
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Access Control
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-private (only-owner)
  (if (is-eq tx-sender (var-get owner))
    (ok true)
    ERR_NOT_OWNER
  )
)

(define-private (only-oracle)
  (if (is-eq tx-sender (var-get oracle))
    (ok true)
    ERR_NOT_ORACLE
  )
)

(define-private (when-active)
  (if (not (var-get paused))
    (ok true)
    ERR_PAUSED
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Admin Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (set-owner (new-owner principal))
  (begin
    (try! (only-owner))
    (var-set owner new-owner)
    (ok true)
  )
)

(define-public (set-oracle (new-oracle principal))
  (begin
    (try! (only-owner))
    (var-set oracle new-oracle)
    (ok true)
  )
)

(define-public (pause-unpause (flag bool))
  (begin
    (try! (only-owner))
    (var-set paused flag)
    (ok (tuple (paused flag)))
  )
)

(define-public (set-fee-bps (new-fee uint))
  (begin
    (try! (only-owner))
    (asserts! (<= new-fee u1000) ERR_INVALID_AMOUNT) ;; max 10%
    (var-set fee-bps new-fee)
    (ok (tuple (fee-bps new-fee)))
  )
)

(define-public (withdraw-treasury (to principal) (amount uint))
  (begin
    (try! (only-owner))
    (asserts! (>= (var-get treasury) amount) ERR_INSUFFICIENT_COLLATERAL)
    (var-set treasury (- (var-get treasury) amount))
    (try! (stx-transfer? amount (as-contract tx-sender) to))
    (ok (tuple (withdrawn amount) (to to)))
  )
)

(define-public (update-collateral-ratio (symbol (string-ascii 8)) (new-ratio uint))
  (begin
    (try! (only-owner))
    (asserts! (>= new-ratio u10000) ERR_INVALID_AMOUNT)
    (match (map-get? synthetic-assets { symbol: symbol })
      asset
      (begin
        (map-set synthetic-assets { symbol: symbol }
          {
            collateral-ratio: new-ratio,
            price:            (get price asset),
            collateral-pool:  (get collateral-pool asset)
          }
        )
        (ok true)
      )
      ERR_ASSET_NOT_FOUND
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Asset Management
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (create-asset (symbol (string-ascii 8)) (collateral-ratio uint) (initial-price uint))
  (begin
    (try! (only-owner))
    (asserts! (>= collateral-ratio u10000) ERR_INVALID_AMOUNT) ;; min 100% collateral
    (asserts! (> initial-price u0) ERR_INVALID_AMOUNT)
    (asserts! (is-none (map-get? synthetic-assets { symbol: symbol })) ERR_ASSET_EXISTS)
    (map-set synthetic-assets { symbol: symbol }
      { collateral-ratio: collateral-ratio, price: initial-price, collateral-pool: u0 })
    (ok (tuple (symbol symbol) (collateral-ratio collateral-ratio) (price initial-price)))
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Oracle Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (update-price (symbol (string-ascii 8)) (new-price uint))
  (begin
    (try! (only-oracle))
    (asserts! (> new-price u0) ERR_INVALID_AMOUNT)
    (match (map-get? synthetic-assets { symbol: symbol })
      asset
      (begin
        (map-set synthetic-assets { symbol: symbol }
          {
            collateral-ratio: (get collateral-ratio asset),
            price:            new-price,
            collateral-pool:  (get collateral-pool asset)
          }
        )
        (ok (tuple (symbol symbol) (price new-price)))
      )
      ERR_ASSET_NOT_FOUND
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Mint / Redeem
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (mint (symbol (string-ascii 8)) (amount uint) (token-contract <token-trait>))
  (begin
    (try! (when-active))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (match (map-get? synthetic-assets { symbol: symbol })
      asset
      (begin
        (let (
          (price (get price asset))
          (ratio (get collateral-ratio asset))
          (pool (get collateral-pool asset))
          (key { user: tx-sender, symbol: symbol })
          (required-collateral (get-required-collateral amount price ratio))
          (after-fee (charge-fee required-collateral))
        )
          (asserts! (> price u0) ERR_PRICE_NOT_SET)

          ;; Transfer collateral from user
          (try! (stx-transfer? required-collateral tx-sender (as-contract tx-sender)))

          ;; Update the synthetic asset's pool
          (map-set synthetic-assets 
            { symbol: symbol }
            { 
              collateral-ratio: ratio,
              price: price,
              collateral-pool: (+ pool after-fee)
            }
          )

          ;; Update user's mint record
          (match (map-get? user-minted key)
            user-entry
            (map-set user-minted key { 
              amount: (+ (get amount user-entry) amount),
              collateral: (+ (get collateral user-entry) after-fee)
            })
            (map-set user-minted key { 
              amount: amount,
              collateral: after-fee
            })
          )

          ;; Mint tokens
          (try! (contract-call? token-contract mint tx-sender amount))

          ;; Final response
          (ok (tuple 
            (minted amount)
            (collateral-required required-collateral)
            (fee-collected (- required-collateral after-fee))
          ))
        )
      )
      ERR_ASSET_NOT_FOUND
    )
  )
)

(define-public (redeem (symbol (string-ascii 8)) (amount uint) (token-contract <token-trait>))
  (begin
    (try! (when-active))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (match (map-get? synthetic-assets { symbol: symbol })
      asset
      (let (
        (price (get price asset))
        (ratio (get collateral-ratio asset))
        (pool (get collateral-pool asset))
        (key { user: tx-sender, symbol: symbol })
      )
        (asserts! (> price u0) ERR_PRICE_NOT_SET)
        (match (map-get? user-minted key)
          user-position
          (let (
            (minted (get amount user-position))
            (user-collateral (get collateral user-position))
            (collateral-per-token (if (> minted u0) (/ user-collateral minted) u0))
            (collateral-to-return (* collateral-per-token amount))
          )
            (asserts! (>= minted amount) ERR_INSUFFICIENT_BALANCE)
            (asserts! (>= user-collateral collateral-to-return) ERR_INSUFFICIENT_COLLATERAL)
            (asserts! (>= pool collateral-to-return) ERR_INSUFFICIENT_COLLATERAL)
            
            ;; Burn tokens first
            (try! (contract-call? token-contract burn tx-sender amount))
            
            ;; Return collateral to user
            (try! (stx-transfer? collateral-to-return (as-contract tx-sender) tx-sender))
            
            ;; Update storage
            (map-set synthetic-assets { symbol: symbol }
              { collateral-ratio: ratio, price: price, collateral-pool: (- pool collateral-to-return) })
            (map-set user-minted key { 
              amount: (- minted amount),
              collateral: (- user-collateral collateral-to-return)
            })
            
            (ok (tuple (redeemed amount) (stx-returned collateral-to-return)))
          )
          ERR_INSUFFICIENT_BALANCE
        )
      )
      ERR_ASSET_NOT_FOUND
    )
  )
)

(define-public (liquidate (user principal) (symbol (string-ascii 8)) (token-contract <token-trait>))
  (begin
    (try! (when-active))
    (match (map-get? synthetic-assets { symbol: symbol })
      asset
      (let (
        (price (get price asset))
        (ratio (get collateral-ratio asset))
        (pool (get collateral-pool asset))
        (key { user: user, symbol: symbol })
      )
        (match (map-get? user-minted key)
          user-position
          (let (
            (minted (get amount user-position))
            (user-collateral (get collateral user-position))
            (required-collateral (get-required-collateral minted price ratio))
          )
            (asserts! (> price u0) ERR_PRICE_NOT_SET)
            (asserts! (> minted u0) ERR_INSUFFICIENT_BALANCE)
            ;; Check if user's position is undercollateralized
            (asserts! (< user-collateral required-collateral) ERR_NOT_UNDERCOLLATERALIZED)
            
            ;; Burn all user's tokens
            (try! (contract-call? token-contract burn user minted))
            
            ;; Transfer user's collateral to liquidator
            (try! (stx-transfer? user-collateral (as-contract tx-sender) tx-sender))
            
            ;; Clear user position and update pool
            (map-set user-minted key { amount: u0, collateral: u0 })
            (map-set synthetic-assets { symbol: symbol }
              { collateral-ratio: ratio, price: price, collateral-pool: (- pool user-collateral) })
            
            (ok (tuple (liquidated user) (symbol symbol) (stx-awarded user-collateral) (tokens-burned minted)))
          )
          ERR_INSUFFICIENT_BALANCE
        )
      )
      ERR_ASSET_NOT_FOUND
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Read-only Views
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-read-only (get-asset-info (symbol (string-ascii 8)))
  (match (map-get? synthetic-assets { symbol: symbol })
    info (ok info)
    ERR_ASSET_NOT_FOUND
  )
)

(define-read-only (get-user-position (user principal) (symbol (string-ascii 8)))
  (match (map-get? user-minted { user: user, symbol: symbol })
    position (ok position)
    (ok { amount: u0, collateral: u0 })
  )
)

(define-read-only (get-collateralization-ratio (user principal) (symbol (string-ascii 8)))
  (match (map-get? synthetic-assets { symbol: symbol })
    asset
    (match (map-get? user-minted { user: user, symbol: symbol })
      position
      (let (
        (minted (get amount position))
        (user-collateral (get collateral position))
        (price (get price asset))
        (required (get-required-collateral minted price (get collateral-ratio asset)))
      )
        (if (> required u0)
          (ok (/ (* user-collateral u10000) required)) ;; Return ratio as basis points
          (ok u0)
        )
      )
      (ok u0)
    )
    ERR_ASSET_NOT_FOUND
  )
)

(define-read-only (get-treasury) (ok (var-get treasury)))
(define-read-only (is-paused) (ok (var-get paused)))
(define-read-only (get-fee-bps) (ok (var-get fee-bps)))
(define-read-only (get-owner) (ok (var-get owner)))
(define-read-only (get-oracle) (ok (var-get oracle)))