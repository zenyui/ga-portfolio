with x as 
(	select TicketDateCalc as 'TicketDate'
			,datepart(hour,tkt_dt) as 'hr'
	from PS_TKT_HIST
	where TicketDateCalc between '2013-12-01' and '2015-12-03'
		and str_id = '1'
		and dbkey = 1
)
select TicketDate, Hr, Count(*) as 'TicketCount'
from x
group by TicketDate, Hr