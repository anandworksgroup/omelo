-- Pin the search_path so schema shadowing cannot change how pay is
-- normalised. This function decides whether a daily-wage job ranks
-- correctly against a salaried one, so it must be deterministic.
alter function public.omelo_pay_monthly(numeric, pay_period, char)
  set search_path = public;