-- =====================================================================
-- OWNER BOOTSTRAP (run once, by JG, in the "3 Salons" SQL Editor).
-- Replace the email with Shahina's real login email. It returns a one-time 16-character code
-- (valid 7 days, single use, bound to that email). Give the code to Shahina privately.
-- She opens https://3salon.netlify.app/join , enters email + code + a password,
-- and becomes the owner. From her Team page she then invites Sofia, Shirin and Sabiha the same way.
-- The code is stored only as a hash; if it is lost, run this again (the old code stops working).
-- =====================================================================
select app.create_owner_invitation('shahina-ahmed', 'OWNER_EMAIL_HERE@example.com');
