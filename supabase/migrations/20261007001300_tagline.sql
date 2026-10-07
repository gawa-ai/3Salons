-- New homepage headline. Only replaces the original staging tagline, so a tagline the owner
-- has edited in Studio -> Settings is never overwritten. Re-runnable.
update app.salons
   set tagline = 'Your moment. Your signature look.'
 where slug = 'shahina-ahmed'
   and tagline = 'Hair, makeup and hijab styling for the moments that matter.';

-- The business name is shown as "Shahina Ahmed" (no "Luxury Salon"). Only replaces the original staging name.
update app.salons set name = 'Shahina Ahmed'
 where slug = 'shahina-ahmed' and name = 'Shahina Ahmed Luxury Salon';
