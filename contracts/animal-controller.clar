;; Animal Controller Smart Contract
;; Manages animal control services with pet licensing and adoption coordination

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-licensed (err u102))
(define-constant err-expired-license (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-already-adopted (err u106))
(define-constant err-not-available (err u107))

;; Animal statuses
(define-constant status-stray u1)
(define-constant status-sheltered u2)
(define-constant status-adopted u3)
(define-constant status-returned-owner u4)
(define-constant status-euthanized u5)

;; License statuses
(define-constant license-active u1)
(define-constant license-expired u2)
(define-constant license-revoked u3)

;; License duration in blocks (approximately 1 year)
(define-constant license-duration u52560)

;; Data Variables
(define-data-var animal-counter uint u0)
(define-data-var license-counter uint u0)
(define-data-var adoption-counter uint u0)
(define-data-var total-adoptions uint u0)
(define-data-var total-licenses uint u0)

;; Data Maps
(define-map animals
  { animal-id: uint }
  {
    species: (string-ascii 30),
    breed: (string-ascii 50),
    color: (string-ascii 30),
    age-estimate: uint,
    rescue-location: (string-ascii 100),
    rescue-date: uint,
    status: uint,
    microchip-id: (optional (string-ascii 20)),
    health-status: (string-ascii 50),
    vaccinations: (string-utf8 200),
    notes: (string-utf8 300)
  }
)

(define-map pet-licenses
  { license-id: uint }
  {
    owner: principal,
    animal-id: (optional uint),
    pet-name: (string-ascii 50),
    species: (string-ascii 30),
    breed: (string-ascii 50),
    microchip-id: (string-ascii 20),
    issue-date: uint,
    expiry-date: uint,
    status: uint,
    vaccination-proof: (string-utf8 200)
  }
)

(define-map adoptions
  { adoption-id: uint }
  {
    animal-id: uint,
    adopter: principal,
    application-date: uint,
    approval-date: (optional uint),
    approved: bool,
    home-check-passed: bool,
    adoption-fee: uint,
    notes: (string-utf8 300)
  }
)

(define-map authorized-officers principal bool)

(define-map owner-licenses
  { owner: principal }
  { license-count: uint, active-licenses: uint }
)

(define-map animal-history
  { animal-id: uint }
  { rescue-count: uint, adoption-count: uint, last-update: uint }
)

;; Authorization Functions
(define-public (add-officer (officer principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-officers officer true))
  )
)

(define-public (remove-officer (officer principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-delete authorized-officers officer))
  )
)

(define-read-only (is-officer (officer principal))
  (default-to false (map-get? authorized-officers officer))
)

;; Animal Management Functions
(define-public (register-stray-animal
  (species (string-ascii 30))
  (breed (string-ascii 50))
  (color (string-ascii 30))
  (age-estimate uint)
  (rescue-location (string-ascii 100))
  (microchip-id (optional (string-ascii 20)))
  (health-status (string-ascii 50))
  (vaccinations (string-utf8 200)))
  (let
    (
      (animal-id (+ (var-get animal-counter) u1))
    )
    (asserts! (or (is-eq tx-sender contract-owner) (is-officer tx-sender)) err-unauthorized)
    
    (map-set animals
      { animal-id: animal-id }
      {
        species: species,
        breed: breed,
        color: color,
        age-estimate: age-estimate,
        rescue-location: rescue-location,
        rescue-date: stacks-block-height,
        status: status-stray,
        microchip-id: microchip-id,
        health-status: health-status,
        vaccinations: vaccinations,
        notes: u""
      }
    )
    
    (map-set animal-history
      { animal-id: animal-id }
      { rescue-count: u1, adoption-count: u0, last-update: stacks-block-height }
    )
    
    (var-set animal-counter animal-id)
    (ok animal-id)
  )
)

(define-public (update-animal-status (animal-id uint) (new-status uint) (notes (string-utf8 300)))
  (let
    (
      (animal (unwrap! (map-get? animals { animal-id: animal-id }) err-not-found))
      (history (default-to 
        { rescue-count: u0, adoption-count: u0, last-update: u0 }
        (map-get? animal-history { animal-id: animal-id })))
    )
    (asserts! (or (is-eq tx-sender contract-owner) (is-officer tx-sender)) err-unauthorized)
    
    (map-set animals
      { animal-id: animal-id }
      (merge animal { status: new-status, notes: notes })
    )
    
    (map-set animal-history
      { animal-id: animal-id }
      (merge history { last-update: stacks-block-height })
    )
    
    (ok true)
  )
)

;; Pet Licensing Functions
(define-public (issue-pet-license
  (pet-name (string-ascii 50))
  (species (string-ascii 30))
  (breed (string-ascii 50))
  (microchip-id (string-ascii 20))
  (vaccination-proof (string-utf8 200)))
  (let
    (
      (license-id (+ (var-get license-counter) u1))
      (owner-stats (default-to 
        { license-count: u0, active-licenses: u0 }
        (map-get? owner-licenses { owner: tx-sender })))
    )
    (map-set pet-licenses
      { license-id: license-id }
      {
        owner: tx-sender,
        animal-id: none,
        pet-name: pet-name,
        species: species,
        breed: breed,
        microchip-id: microchip-id,
        issue-date: stacks-block-height,
        expiry-date: (+ stacks-block-height license-duration),
        status: license-active,
        vaccination-proof: vaccination-proof
      }
    )
    
    (map-set owner-licenses
      { owner: tx-sender }
      {
        license-count: (+ (get license-count owner-stats) u1),
        active-licenses: (+ (get active-licenses owner-stats) u1)
      }
    )
    
    (var-set license-counter license-id)
    (var-set total-licenses (+ (var-get total-licenses) u1))
    (ok license-id)
  )
)

(define-public (renew-license (license-id uint))
  (let
    (
      (license (unwrap! (map-get? pet-licenses { license-id: license-id }) err-not-found))
    )
    (asserts! (is-eq (get owner license) tx-sender) err-unauthorized)
    
    (map-set pet-licenses
      { license-id: license-id }
      (merge license {
        expiry-date: (+ stacks-block-height license-duration),
        status: license-active
      })
    )
    
    (ok true)
  )
)

(define-public (revoke-license (license-id uint))
  (let
    (
      (license (unwrap! (map-get? pet-licenses { license-id: license-id }) err-not-found))
      (owner-stats (default-to 
        { license-count: u0, active-licenses: u0 }
        (map-get? owner-licenses { owner: (get owner license) })))
    )
    (asserts! (or (is-eq tx-sender contract-owner) (is-officer tx-sender)) err-unauthorized)
    
    (map-set pet-licenses
      { license-id: license-id }
      (merge license { status: license-revoked })
    )
    
    (map-set owner-licenses
      { owner: (get owner license) }
      {
        license-count: (get license-count owner-stats),
        active-licenses: (if (> (get active-licenses owner-stats) u0)
          (- (get active-licenses owner-stats) u1)
          u0)
      }
    )
    
    (ok true)
  )
)

;; Adoption Functions
(define-public (submit-adoption-application
  (animal-id uint)
  (home-check-passed bool)
  (adoption-fee uint)
  (notes (string-utf8 300)))
  (let
    (
      (animal (unwrap! (map-get? animals { animal-id: animal-id }) err-not-found))
      (adoption-id (+ (var-get adoption-counter) u1))
    )
    (asserts! (or (is-eq (get status animal) status-stray) (is-eq (get status animal) status-sheltered)) err-not-available)
    
    (map-set adoptions
      { adoption-id: adoption-id }
      {
        animal-id: animal-id,
        adopter: tx-sender,
        application-date: stacks-block-height,
        approval-date: none,
        approved: false,
        home-check-passed: home-check-passed,
        adoption-fee: adoption-fee,
        notes: notes
      }
    )
    
    (var-set adoption-counter adoption-id)
    (ok adoption-id)
  )
)

(define-public (approve-adoption (adoption-id uint) (approved bool))
  (let
    (
      (adoption (unwrap! (map-get? adoptions { adoption-id: adoption-id }) err-not-found))
      (animal (unwrap! (map-get? animals { animal-id: (get animal-id adoption) }) err-not-found))
      (history (default-to 
        { rescue-count: u0, adoption-count: u0, last-update: u0 }
        (map-get? animal-history { animal-id: (get animal-id adoption) })))
    )
    (asserts! (or (is-eq tx-sender contract-owner) (is-officer tx-sender)) err-unauthorized)
    
    (map-set adoptions
      { adoption-id: adoption-id }
      (merge adoption {
        approved: approved,
        approval-date: (some stacks-block-height)
      })
    )
    
    (if approved
      (begin
        (map-set animals
          { animal-id: (get animal-id adoption) }
          (merge animal { status: status-adopted })
        )
        (map-set animal-history
          { animal-id: (get animal-id adoption) }
          {
            rescue-count: (get rescue-count history),
            adoption-count: (+ (get adoption-count history) u1),
            last-update: stacks-block-height
          }
        )
        (var-set total-adoptions (+ (var-get total-adoptions) u1))
        (ok true)
      )
      (ok true)
    )
  )
)

;; Read-Only Functions
(define-read-only (get-animal (animal-id uint))
  (map-get? animals { animal-id: animal-id })
)

(define-read-only (get-license (license-id uint))
  (map-get? pet-licenses { license-id: license-id })
)

(define-read-only (get-adoption (adoption-id uint))
  (map-get? adoptions { adoption-id: adoption-id })
)

(define-read-only (get-animal-history (animal-id uint))
  (map-get? animal-history { animal-id: animal-id })
)

(define-read-only (get-owner-licenses (owner principal))
  (map-get? owner-licenses { owner: owner })
)

(define-read-only (is-license-valid (license-id uint))
  (match (map-get? pet-licenses { license-id: license-id })
    license (ok (and
      (is-eq (get status license) license-active)
      (>= (get expiry-date license) stacks-block-height)
    ))
    err-not-found
  )
)

(define-read-only (get-total-adoptions)
  (ok (var-get total-adoptions))
)

(define-read-only (get-total-licenses)
  (ok (var-get total-licenses))
)

(define-read-only (get-animal-counter)
  (ok (var-get animal-counter))
)

;; Initialize contract owner as authorized officer
(map-set authorized-officers contract-owner true)
