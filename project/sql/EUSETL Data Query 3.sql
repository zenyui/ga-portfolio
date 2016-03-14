use cpsql;

--get sales outlets
--drop table #DimSalesOutlet
select L.DBKey, L.CPStoreID, L.CPCategory, S.SalesOutletKey, S.SalesOutletName, S.SalesOutletType, St.Location
into #DimSalesOutlet
from eusdw.StageDW.[dbo].[LookupCPSalesOutlet] L
inner join eusdw.eatalydw.dbo.dimsalesoutlet s on L.SalesOutletKey = S.SalesOutletKey
inner join eusdw.eatalydw.dbo.dimstore st on s.storekey = st.storekey;

create unique clustered index ix_pk on #DimSalesOutlet(DBKey, CPStoreID, CPCategory);

--select * from #DimSalesOutlet

--get pos station
--drop table #DimPosStation
select PosStationKey, DBKey, BKPosStationID, Seq, StationGroup 
into #DimPosStation
from eusdw.eatalydw.dbo.dimposstation;

create unique clustered index ix on #DimPosStation (DBKey, BKPosStationID, Seq)

--select * from #DimSalesOutlet
--DROP TABLE #TicketHeader
Create table #TicketHeader
(	DBKey	int
	,BUS_DAT	date
	,DOC_ID		BIGINT
	,PMT_SEQ_NO	INT
	,STR_ID		VARCHAR(10)
	,TicketDate	date
	,TicketTime	time(0)
	,CC4		varchar(4)
	,CCFullName	varchar(50)
	,CCLastName	varchar(50)
	,STA_ID		varchar(10)
	,PosSeqNo	int
	,StationGroup	varchar(20)
	,GiftCardLines	int
);

--get data
insert into #TicketHeader
(	DBKey
	,BUS_DAT
	,DOC_ID
	,PMT_SEQ_NO
	,STR_ID
	,TicketDate
	,TICKETTIME
	,CC4
	,CCFullName
	,STA_ID
	,PosSeqNo
	,GiftCardLines
)
select C.DBKey
	,C.BUS_DAT
	,C.DOC_ID
	,C.PMT_SEQ_NO
	,c.STR_ID
	,C.TicketDateCalc as 'TicketDate'
	,convert(time(0),c.TKT_DT) as 'TicketTime'
	,right(CR_CARD_NO_MSK,4) as 'CC4'
	,upper(ltrim(rtrim(CR_CARD_NAM))) as 'CCFullName'
	,H.STA_ID
	,L.SEQ as 'PosSeqNo'
	,H.SVC_LINS
from dbo.PS_TKT_HIST_PMT_CR_CARD c
inner join dbo.PS_TKT_HIST H
	ON C.DBKey = H.DBKey
	AND C.BUS_DAT = H.BUS_DAT
	AND C.DOC_ID = H.DOC_ID
inner join dbo.lookupCPStation l
	on h.dbkey = l.dbkey
	and h.str_id = l.str_id
	and h.sta_id = l.sta_id
where C.TicketDateCalc between '2013-09-01' and '2016-03-03'
	and C.CR_CARD_NO_MSK is not null
	and C.CR_CARD_NAM is not null
	AND LEFT(H.CUST_NO,3) <> 'EMP' --filter out employees
	and C.DBKey = 1
	and C.STR_ID = '1';

update #TicketHeader
set CCLastName = case CHARINDEX(' ',reverse(CCFullName)) 
					when 0 then CCFullName 
					else ltrim(right(CCFullName,CHARINDEX(' ',reverse(CCFullName)))) 
				end;

--get pos station key
update x
set StationGroup = P.Stationgroup
from #TicketHeader x
inner join #DimPosStation P
on x.DBKey = P.DBKey
	and X.STA_ID = P.BKPosStationID
	and X.PosSeqNo = P.Seq

--select top 100 * from #TicketHeader

raiserror('ticket header done',0,1) with nowait;

--lines data
--drop table #TicketLines
Create table #TicketLines
(	DBKey int
	,BUS_DAT date
	,DOC_ID bigint
	,PMT_SEQ_NO int
	,LIN_SEQ_NO int
	,LIN_TYP VARCHAR(2)
	,STR_ID VARCHAR(10)
	,SKU varchar(20)
	,Category varchar(20)
	,Subcategory varchar(20)
	,QtySold decimal(18,4)
	,GrossAmount decimal(18,2)
	,NetAmount decimal(18,2)
	,DiscountAmount decimal(18,2)
	,SalesOutletKey int
	,SalesOutletType	varchar(20)
)

create unique clustered index ix_pk on #TicketLines (DBKey, BUS_DAT, DOC_ID, PMT_SEQ_NO, LIN_SEQ_NO);
create index ix_item on #TicketLines(SKU);

insert into #TicketLines 
(	DBKey
	,BUS_DAT
	,DOC_ID
	,PMT_SEQ_NO
	,LIN_SEQ_NO
	,LIN_TYP
	,STR_ID
	,SKU
	,Category
	,Subcategory
	,QtySold
	,GrossAmount
	,NetAmount
	--,DiscountAmount
)
select	l.DBKey
		,l.BUS_DAT
		,l.DOC_ID
		,H.pmt_seq_no
		,l.LIN_SEQ_NO
		,L.LIN_TYP
		,l.STR_ID
		,l.ITEM_NO
		,l.MaxCategory
		,L.SUBCAT_COD
		,l.QTY_SOLD * l.QTY_NUMER / l.QTY_DENOM
		,l.GROSS_EXT_PRC
		,l.EXT_PRC
		--,l.GROSS_EXT_PRC - l.EXT_PRC
from dbo.PS_TKT_HIST_lin L
inner join #TicketHeader H
	on L.DBKey = H.DBKey
	and L.BUS_DAT = H.BUS_DAT
	and l.DOC_ID = H.DOC_ID
where l.TicketDateCalc between '2013-09-01' and '2016-03-03'
	and L.STR_ID = '1'
	and L.DBKey = 1;

--calc discount amount
update #ticketLines set DiscountAmount = GrossAmount - NetAmount

--get sales outlet info
update x
set SalesOutletKey = S.SalesoutletKey
	,SalesOutletType = S.SalesOutletType
from #TicketLines x
inner join #DimSalesOutlet S
	on X.DBKey = S.DBKey
	and X.STR_ID = s.CPSToreID
	and X.Category = S.CPCategory

--select top 100 * from #TicketLines;
raiserror('ticket lines done',0,1) with nowait;



--get distinct tickets with lines
select DISTINCT DBKey, BUS_DAT, DOC_ID
into #ticketfilter
from #ticketlines

--delete tickets with no lines
delete h
from #ticketHeader h
left outer join #ticketfilter F
	on h.dbkey = f.dbkey
	and h.bus_dat = f.bus_dat
	and h.doc_id = f.doc_id
where f.DBKey is null

raiserror('deleted tickets with no lines',0,1) with nowait;




--output table
--drop table #CustPayments
create table #CustPayments
(	 DBKey				int
	,BUS_DAT			date
	,DOC_ID				bigint
	,PMT_SEQ_NO			int
	,CustomerKey		bigint
	,VisitNumber		int
	,VisitCount			int --probably not a fair metric
	,TicketDate			date
	,TicketTime			time(0)
	,PriorVisits		int
	,SaleLines			int
	,ReturnLines		int --may not have enough diversity to be a good feature
	,GiftCardLines		int --may not have enough diversity to be a good feature
	,ProduceLines		int	default 0
	,MeatLines			int	default 0
	,FishLines			int default 0
	,OilLines			int	default 0
	,FreshPastaLines	int	default 0
	,SAFOLines			int	default 0
	,RotisserieLines	int	default 0
	,NetAmount			decimal(18,2)
	,NetRetailAmount	decimal(18,2)
	,NetQSRAmount		decimal(18,2)
	,DiscountAmount		decimal(18,2)
	,StationGroup		varchar(20)
	,UniqueItems		int
	,UniqueCategories	int
	,ReturnedBags		bit --returned bags and got bag deposit
	,TopItemLines		int default 0
	,RepeatProducts		int default 0 -- count of products in current basket that were purchased last visit
	,WillReturn			bit default 0
	--,BoughtProduce		bit --bought produce during trip
);


create unique clustered index ix on #CustPayments (DBKey, BUS_DAT, DOC_ID, PMT_SEQ_NO);

insert into #CustPayments 
(	DBKey
	,BUS_DAT
	,DOC_ID
	,PMT_SEQ_NO
	,CustomerKey
	,VisitNumber
	,VisitCount
	,TicketDate
	,TicketTime
	,StationGroup
	,GiftCardLines
	--,PriorVisits
	--,STR_ID
)
select DBKey
	,BUS_DAT
	,DOC_ID
	,PMT_SEQ_NO
	,DENSE_RANK() OVER (order by CC4, CCLastName) as 'CustomerKey'
	,ROW_NUMBER() over (Partition by CC4, CCLastName order by TicketDate, TicketTime) as 'VisitNumber'
	,count(*) over (Partition by CC4, CCLastName) as 'VisitCount'
	,TicketDate
	,TicketTime
	,StationGroup
	,GiftCardLines
	--,ROW_NUMBER() over (Partition by CC4, CCLastName order by TicketDate, TicketTime) -1 as 'PriorVisits'
	--,STR_ID
from #TicketHeader

update #CustPayments set PriorVisits = VisitNumber -1

raiserror('cust payments loaded',0,1) with nowait;

--find repeat customers
update P1
set WillReturn = 1
from #CustPayments P1
inner join #CustPayments P2
	on P1.CustomerKey = P2.CustomerKey
	and P1.VisitNumber = p2.VisitNumber -1
Where P1.VisitCount > 1
	and P2.VisitCount > 1
	and datediff(day, p1.TicketDate, p2.TicketDate) < 90

raiserror('repeats found',0,1) with nowait;
--select top 1000 * from #CustPayments

--agg best selling items of repeat customers
--drop table #BestSellers
CREATE TABLE #BestSellers
(	SKU VARCHAR(20)
	,TicketCount	int
	,rn	int
);

create unique clustered index ix on #BestSellers (SKU);

with x as
(	select L.SKU, COUNT(DISTINCT CONVERT(VARCHAR(10), L.BUS_DAT) + CONVERT(VARCHAR(20), L.DOC_ID)) as 'TicketCount'
	from #ticketlines L
	inner join #custpayments C
		on L.DBKEY = C.DBKey
		AND l.BUS_DAT = c.BUS_DAT
		AND l.DOC_ID = C.DOC_ID
	WHERE C.WillReturn = 1
	GROUP BY L.SKU
)
insert into #BestSellers (SKU, TicketCount, rn)
select *, ROW_NUMBER() over (order by TicketCount desc) as 'rn'
from x

delete #BestSellers where rn > 100;
--select * from #BestSellers

--drop table #LinesAgg
create table #LinesAgg
(	DBKey				int
	,bus_dat			date
	,doc_id				bigint
	,pmt_seq_no			int
	,GrossAmount		decimal(18,2)
	,NetAmount			decimal(18,2)
	,DiscountAmount		decimal(18,2)
	,NetRetailAmount	decimal(18,2)
	,NetQSRAmount		decimal(18,2)
	,UniqueItems		int
	,UniqueCategories	int
	,SaleLines			int
	,ReturnLines		int
	,ReturnedBags		bit
	,ProduceLines		int	default 0
	,MeatLines			int	default 0
	,FishLines			int	default 0
	,OilLines			int	default 0
	,FreshPastaLines	int	default 0
	,SAFOLines			int	default 0
	,RotisserieLines	int	default 0
	,TopItemLines		int default 0
);

create unique clustered index ix_pk on #LinesAgg (DBKey, bus_dat, doc_id, pmt_seq_no);

insert into #LinesAgg
(	DBKey
	,bus_dat
	,doc_id
	,pmt_seq_no
	,GrossAmount
	,NetAmount
	,DiscountAmount
	,UniqueItems
	,UniqueCategories
	,NetRetailAmount
	,NetQSRAmount
	,SaleLines
	,ReturnLines
	,ReturnedBags
	,ProduceLines
	,MeatLines
	,FishLines
	,OilLines
	,FreshPastaLines
	,SAFOLines
	,RotisserieLines
	,TopItemLines
)
select	DBKey
		,BUS_DAT
		,DOC_ID
		,PMT_SEQ_NO
		,sum(GrossAmount)
		,sum(NetAmount)
		,sum(DiscountAmount)
		,count(distinct L.SKU)
		,count(distinct Category)
		,sum(case when SalesOutletType = 'Retail' then NetAmount else 0 end)
		,sum(case when SalesOutletType = 'QSR' then NetAmount else 0 end)
		,sum(case when L.LIN_TYP = 'S' THEN 1 ELSE 0 END)
		,sum(case when L.LIN_TYP = 'R' THEN 1 ELSE 0 END)
		,case when sum(case when L.Category = 'BAGREUSE' then 1 else 0 end) > 0 then 1 else 0 end --,ReturnedBags
		
		,sum(case when L.Category in ('FRUIT','VEGETABLE') then 1 else 0 end)  --producelines
		,sum(case when L.Category = 'MEAT' then 1 else 0 end) --meat lines
		,sum(case when L.Category = 'FISH' then 1 else 0 end) --FISH LINES
		,sum(case when L.Category = 'CONDIMENTS' AND L.Subcategory = 'OIL' then 1 else 0 end) --Oil
		,sum(case when L.Category = 'FRESH PAST' then 1 else 0 end) --Fresh Pasta
		,sum(case when L.Category in ('SALUMI','CHEESE') then 1 else 0 end)  --SAFO
		,sum(case when L.Category = 'ROTISSERIE' then 1 else 0 end) --rotisserie
		,sum(case when B.SKU is not null then 1 else 0 end) --top selling items count
from #TicketLines L
left outer join #BestSellers B on L.SKU = B.SKU
Group by DBKey, BUS_DAT, DOC_ID, PMT_SEQ_NO;

raiserror('lines agg done',0,1) with nowait;

update x
set NetAmount = L.NetAmount
	,NetRetailAmount = L.NetRetailAmount
	,NetQSRAmount = L.NetQSRAmount
	,DiscountAmount = L.DiscountAmount
	,UniqueItems = L.UniqueItems
	,UniqueCategories = L.UniqueCategories
	,SaleLines = L.SaleLines
	,ReturnLines = L.ReturnLines
	,Returnedbags = L.ReturnedBags
	,ProduceLines = L.ProduceLines
	,MeatLines = L.MeatLines
	,FishLines = L.FishLines
	,OilLines = L.OilLines
	,FreshPastaLines = L.FreshPastaLines
	,SAFOLines = L.SAFOLines
	,RotisserieLines = L.RotisserieLines
	,TopItemLines = L.TopItemLines
from #CustPayments x
inner join #LinesAgg L
	on x.DBKey = L.DBKey
	and x.BUS_DAT = L.BUS_DAT
	and x.DOC_ID = L.DOC_ID
	and x.PMT_SEQ_NO = l.PMT_SEQ_NO

raiserror('lines agg applied to cust payments done',0,1) with nowait;

--find repeat products from last visit
with x as (
	select distinct P.CustomerKey, P.VisitNumber, l.sku
	from #TicketLines L
	inner join #CustPayments P
		on L.DBKey = P.DBKey
		and L.BUS_DAT = P.BUS_DAt
		and L.DOC_ID = P.DOC_ID
	where P.VisitCount > 1
)
,rep as
(	select x1.CustomerKey, x1.VisitNumber, count(*) as 'RepeatProducts'
	from x x1
	inner join x x2
		on x1.CustomerKey = x2.CustomerKey
		and x1.SKU = x2.SKU
		and x1.VisitNumber = x2.VisitNumber + 1
	group by x1.CustomerKey, x1.VisitNumber
)

update C
set RepeatProducts = R.RepeatProducts
from #CustPayments C
inner join rep R
	on C.CustomerKey = R.CustomerKey
	 and C.VisitNumber = R.VisitNumber;

select * from #CustPayments

--drop table etldb.dbo.ZenGAProject
--select * from etldb.dbo.ZenGAProject

select * 
into etldb.dbo.ZenGAProject
from #CustPayments
where TicketDate between '2013-12-01' and '2015-12-03'

raiserror('final insert done',0,1) with nowait;


select * from etldb.dbo.ZenGAProject