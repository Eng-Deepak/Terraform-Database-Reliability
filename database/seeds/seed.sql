INSERT INTO hotel_bookings (
    org_id,
    hotel_id,
    city,
    checkin_date,
    checkout_date,
    amount,
    status,
    created_at
)
SELECT
    ('00000000-0000-0000-0000-' ||
     LPAD((i % 5 + 1)::TEXT, 12, '0'))::UUID,

    'HOTEL-' || i,

    CASE
        WHEN i % 3 = 0 THEN 'delhi'
        WHEN i % 3 = 1 THEN 'mumbai'
        ELSE 'jaipur'
    END,

    CURRENT_DATE + 10,
    CURRENT_DATE + 12,

    (1000 + i * 100)::NUMERIC(12,2),

    CASE
        WHEN i % 3 = 0 THEN 'confirmed'
        WHEN i % 3 = 1 THEN 'cancelled'
        ELSE 'pending'
    END,

    NOW() - (i || ' days')::INTERVAL

FROM generate_series(1, 120) AS i;


INSERT INTO booking_events (
    booking_id,
    event_type,
    payload
)
SELECT
    id,
    'booking_created',
    '{"source":"web","payment":"pending"}'::JSONB
FROM hotel_bookings
WHERE id IN (
    SELECT id
    FROM hotel_bookings
    ORDER BY created_at DESC
    LIMIT 30
);
