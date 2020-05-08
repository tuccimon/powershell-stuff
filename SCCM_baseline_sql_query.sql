exec sp_executesql N'

          declare @allassignments table
          (
          AssignmentID int,
          CollectionID  nvarchar(512),
          CollecionName nvarchar(512),
          CI_ID         int,
          DisplayName nvarchar(512),
          CIType_ID   int,
          CI_UniqueID nvarchar(512),
          CIVersion     int,
          Level         int,
          deepsortorder nvarchar(1024)
          )

          declare @AllCIs table
          (
          BL_CI_ID      int,
          CI_ID         int,
          CI_ModelID    int,
          CIVersion     int,
          CI_UniqueID   nvarchar(512),
          CIType_ID     int,
          RelationType  int,
          BLDisplayName nvarchar(512),
          DisplayName   nvarchar(512),
          Categories    nvarchar(512)
          )
          
            DECLARE @SummarizedCIs TABLE 
            (
            CI_ModelID int,
            CIVersion int,
            CountReported int,
            CountTargeted int,
            CountUnknown int, 
            CountCompliant int, 
            FailureCount int, 
            CountNoncompliant int, 
            CountEnforced int, 
            CountNotApplicable int, 
            CountNotDetected int, 
            Severity int
            )

          declare @lcid as int set @lcid = dbo.fn_LShortNameToLCID(@locale)

          --recursively select all sub-baselines along with the sort order
          ;WITH AllBaselines(AssignmentID,CollectionID,CollecionName,CI_ID, CIVersion, CI_UniqueID, Level, deepsortorder, DisplayName)
          AS
          (
          select AssignmentID=assign.AssignmentID,CollectionID=coll.CollectionID,CollecionName=coll.Name,CI_ID=ci.CI_ID,ci.CIVersion,CI_UniqueID, Level=0, convert(varchar(1024),(ci.CI_ID)), dbo.fn_GetLocalizedCIName(@lcid,ci.CI_ID)
          from
          v_CIAssignment  assign
          inner join fn_rbac_Collection(@UserSIDs)  coll on coll.CollectionID=assign.CollectionID
          inner join v_CIAssignmentToCI  targ on targ.AssignmentID=assign.AssignmentID
          inner join v_CIRelation_All  rel on rel.CI_ID=targ.CI_ID
          inner join fn_rbac_ConfigurationItems(@UserSIDs)  ci on ci.CI_ID=rel.ReferencedCI_ID          
          where CIType_ID=2
          and (dbo.fn_GetLocalizedCIName(@lcid,ci.CI_ID) = @name  or @name = '''')
          and (coll.CollectionID=@collid or @collid='''' or @collid is NULL)
          and(assign.AssignmentID=@assignmentID or @assignmentID='''' or @assignmentID is NULL)
          and assign.AssignmentType=0
          union all
          select bci.AssignmentID,bci.CollectionID,bci.CollecionName,rci.ToCIID,ci.CIVersion, ci.CI_UniqueID, Level=Level+1, convert(varchar(1024), deepsortorder+''-''+convert(varchar(32),rci.ToCIID)), dbo.fn_GetLocalizedCIName(@lcid,ci.CI_ID)
          from AllBaselines bci
          inner join v_CIRelation  rci on rci.FromCIID=bci.CI_ID and rci.RelationType=1
          inner join fn_rbac_ConfigurationItems(@UserSIDs)  ci on ci.CI_ID=rci.ToCIID
          where ci.CIType_ID=2
          )
          Insert into @allassignments (AssignmentID,CollectionID,CollecionName,CI_ID,CIVersion,CI_UniqueID, Level, deepsortorder, DisplayName)
          select AssignmentID,CollectionID,CollecionName,CI_ID,CIVersion,CI_UniqueID, Level, deepsortorder, DisplayName from AllBaselines


          --select all CIs along with the sort order
          Insert into @AllCIs
          select distinct rel.FromCIID,rel.ToCIID,ciref.ModelId,ciref.CIVersion,ciref.CI_UniqueID,ciref.CIType_ID,rel.RelationType,dbo.fn_GetLocalizedCIName(@lcid,bl.CI_ID) as BLDisplayName, dbo.fn_GetLocalizedCIName(@lcid,ciref.CI_ID), dbo.fn_BuildLocalizedCICategories(ciref.CI_ID, @lcid)
           from
          @allassignments bl
          inner join  v_CIRelation  rel on rel.FromCIID=bl.CI_ID
          inner join fn_rbac_ConfigurationItems(@UserSIDs)  ciref on ciref.CI_ID=rel.ToCIID
          left join
          (
          select distinct CI_ID from fn_CICategoryInfo(@lcid)  cat
          where cat.CategoryInstanceName = @category or @category=''''
          )tempcat on tempcat.CI_ID=ciref.CI_ID
          where
          rel.RelationType in (0, 1, 2, 3, 4)
          and ciref.IsTombstoned=0
          and (tempcat.CI_ID is not null or @category='''')


          declare @temp_ModelID as int
          declare @temp_CIVersion as int
          
          DECLARE curs cursor local fast_forward FOR
            SELECT distinct CI_ModelID,CIVersion from @AllCIs
                
          OPEN curs
          FETCH curs INTO @temp_ModelID, @temp_CIVersion
        
          WHILE @@FETCH_STATUS = 0
          BEGIN     

          INSERT INTO @SummarizedCIs(CI_ModelID,CIVersion,CountReported,CountTargeted,CountUnknown,CountCompliant,FailureCount,CountNoncompliant,CountEnforced,CountNotApplicable,CountNotDetected,Severity)
          select
          TargetsSummarized.CI_ModelID,CIVersion,
          count(TargetsSummarized.TargetID) as CountReported,
          count(TargetsSummarized.TargetID) as CountTargeted,
          sum(case when (TargetsSummarized.UnknownTargets is NULL) then 1 else 0 end) as CountUnknown, -- CountUnknown
          sum(case when (TargetsSummarized.NonCompliantTargets = 0) and (TargetsSummarized.ErroredTargets = 0) and (TargetsSummarized.UnknownTargets = 0)
          and(TargetsSummarized.NotApplicableTargets=0)and TargetsSummarized.NotDetectedTargets=0   then 1 else 0 end) as CountCompliant, -- CountCompliant

          sum(case when (TargetsSummarized.ErroredTargets > 0)                                                                                       then 1 else 0 end) as FailureCount, -- FailureCount
          sum(case when (TargetsSummarized.NonCompliantTargets > 0) and (TargetsSummarized.ErroredTargets = 0)                                       then 1 else 0 end) as CountNoncompliant, -- CountNoncompliant
          sum(case when (TargetsSummarized.EnforcedTargets > 0)                                                                                      then 1 else 0 end) as CountEnforced, -- CountEnforced
          sum(case when (TargetsSummarized.NotApplicableTargets > 0)                                                                                 then 1 else 0 end) as CountNotApplicable, -- CountNotApplicable
          sum(case when (TargetsSummarized.NotDetectedTargets > 0)                                                                                   then 1 else 0 end) as CountNotDetected, -- CountNotDetected
          max(isnull(TargetsSummarized.MaxUsersNoncomplianceCriticality, 0)) as Severity -- Severity


          from
          (

          select machines.CI_ModelID,machines.CIVersion,sys.ResourceID as TargetID,UsersSummarized.CompliantTargets,UsersSummarized.NonCompliantTargets,UsersSummarized.UnknownTargets,
          UsersSummarized.ErroredTargets,UsersSummarized.EnforcedTargets,UsersSummarized.NotApplicableTargets,UsersSummarized.NotDetectedTargets,UsersSummarized.MaxUsersNoncomplianceCriticality
          from
          (
              select distinct
              AllCIs.CI_ModelID,AllCIs.CIVersion,cm.ResourceID
              from  @allassignments allbl
              inner join @AllCIs AllCIs on allbl.CI_ID=AllCIs.BL_CI_ID
              inner join v_ClientCollectionMembers  cm on cm.CollectionID=allbl.CollectionID
              join fn_rbac_Collection(@UserSIDs) coll on coll.CollectionID = cm.CollectionID
              where AllCIs.CI_ModelID=@temp_ModelID and AllCIs.CIVersion=@temp_CIVersion
          ) machines            
          inner join v_R_System_Valid  sys on sys.ResourceID=machines.ResourceID
          left join
          (
              select ItemKey,
              sum(case when ComplianceState  = 1 and IsDetected  =1   and IsApplicable=1 then 1 else 0 end) as CompliantTargets,
              sum(case when ComplianceState  = 2 and IsDetected  =1   and IsApplicable=1 then 1 else 0 end) as NonCompliantTargets,
              sum(case when ComplianceState  = 3                                         then 1 else 0 end) as UnknownTargets,
              sum(case when ComplianceState  = 4                                         then 1 else 0 end) as ErroredTargets,
              sum(case when IsEnforced       = 1 and IsDetected  =1   and IsApplicable=1 then 1 else 0 end) as EnforcedTargets,
              sum(case when ComplianceState != 4 and IsApplicable=0                      then 1 else 0 end) as NotApplicableTargets,
              sum(case when ComplianceState != 4 and IsDetected = 0   and IsApplicable=1 then 1 else 0 end) as NotDetectedTargets,
              MAX(isnull(MaxNoncomplianceCriticality,0))           as MaxUsersNoncomplianceCriticality
              from v_SMSCICurrentComplianceStatus  curr
              inner join
              ( select MAX(assstatus.LastEvaluationMessageTime) as LastComplianceMessageTime,ResourceID,UserID,CI_ID as BL_ID  from v_CIAssignmentStatus  assstatus
                join @allassignments cis on cis.AssignmentID = assstatus.AssignmentID 
                group by ResourceID,UserID,CI_ID
              ) assstatus on assstatus.ResourceID=curr.ItemKey and assstatus.UserID=curr.UserID
              where curr.ModelID=@temp_ModelID and CIVersion=@temp_CIVersion
              group by ItemKey
          ) UsersSummarized on UsersSummarized.ItemKey = sys.ResourceID
          ) TargetsSummarized
          group by
          TargetsSummarized.CI_ModelID,
          TargetsSummarized.CIVersion
          --next fetch
          FETCH curs INTO @temp_ModelID, @temp_CIVersion
          END

          CLOSE curs
          DEALLOCATE curs
          
          
          
          DECLARE curs cursor local fast_forward FOR
            SELECT distinct CI_ModelID,CIVersion from @AllCIs
                
          OPEN curs
          FETCH curs INTO @temp_ModelID, @temp_CIVersion

          WHILE @@FETCH_STATUS = 0
          BEGIN


          INSERT INTO @SummarizedCIs(CI_ModelID,CIVersion,CountReported,CountTargeted,CountUnknown,CountCompliant,FailureCount,CountNoncompliant,CountEnforced,CountNotApplicable,CountNotDetected,Severity)
          select 
          TargetsSummarized.CI_ModelID,
          TargetsSummarized.CIVersion,
          count(TargetsSummarized.TargetID) as CountReported,
          count(TargetsSummarized.TargetID) as CountTargeted,
          sum(case when (TargetsSummarized.UnknownTargets is NULL) then 1 else 0 end) as CountUnknown, -- CountUnknown
          sum(case when (TargetsSummarized.NonCompliantTargets = 0) and (TargetsSummarized.ErroredTargets = 0) and (TargetsSummarized.UnknownTargets = 0)
          and(TargetsSummarized.NotApplicableTargets=0)and TargetsSummarized.NotDetectedTargets=0   then 1 else 0 end) as CountCompliant, -- CountCompliant

          sum(case when (TargetsSummarized.ErroredTargets > 0)                                                                                       then 1 else 0 end) as FailureCount, -- FailureCount
          sum(case when (TargetsSummarized.NonCompliantTargets > 0) and (TargetsSummarized.ErroredTargets = 0)                                       then 1 else 0 end) as CountNoncompliant, -- CountNoncompliant
          sum(case when (TargetsSummarized.EnforcedTargets > 0)                                                                                      then 1 else 0 end) as CountEnforced, -- CountEnforced
          sum(case when (TargetsSummarized.NotApplicableTargets > 0)                                                                                 then 1 else 0 end) as CountNotApplicable, -- CountNotApplicable
          sum(case when (TargetsSummarized.NotDetectedTargets > 0)                                                                                   then 1 else 0 end) as CountNotDetected, -- CountNotDetected
          max(isnull(TargetsSummarized.MaxUsersNoncomplianceCriticality, 0)) as Severity -- Severity
          from
          (
          select users.CI_ModelID,users.CIVersion,users.UserName as TargetID,MachinesSummarized.CompliantTargets,MachinesSummarized.NonCompliantTargets,MachinesSummarized.UnknownTargets,
          MachinesSummarized.ErroredTargets,MachinesSummarized.EnforcedTargets,MachinesSummarized.NotApplicableTargets,MachinesSummarized.NotDetectedTargets,MachinesSummarized.MaxUsersNoncomplianceCriticality
     
          from 
          (   
              select distinct
              AllCIs.CI_ModelID,AllCIs.CIVersion,resources.UserName
              from @allassignments allbl
              inner join @AllCIs AllCIs on allbl.CI_ID=AllCIs.BL_CI_ID
              inner join v_dcmdeploymentresourcesuser  resources on resources.AssignmentID=allbl.AssignmentID
              join fn_rbac_Collection(@UserSIDs) coll on coll.CollectionID = resources.CollectionID
              where AllCIs.CI_ModelID=@temp_ModelID and AllCIs.CIVersion=@temp_CIVersion
          ) users             
          left join
          (--get user data for all machines that the user logged on to
          select curr.UserID,Users.FullName as UserName,
          sum(case when ComplianceState = 1 and IsDetected=1   and IsApplicable=1 then 1 else 0 end) as CompliantTargets,
          sum(case when ComplianceState = 2 and IsDetected=1   and IsApplicable=1 then 1 else 0 end) as NonCompliantTargets,
          sum(case when ComplianceState = 3 then 1 else 0 end) as UnknownTargets,
          sum(case when ComplianceState = 4 then 1 else 0 end) as ErroredTargets,
          sum(case when IsEnforced = 1      and IsDetected=1   and IsApplicable=1 then 1 else 0 end) as EnforcedTargets,
          sum(case when IsApplicable=0                                            then 1 else 0 end) as NotApplicableTargets,
          sum(case when IsDetected = 0      and IsApplicable=1                    then 1 else 0 end) as NotDetectedTargets,
          MAX(isnull(MaxNoncomplianceCriticality,0))           as MaxUsersNoncomplianceCriticality
          from v_SMSCICurrentComplianceStatus  curr
          join v_Users  users on users.UserID=curr.UserID
          where ModelID=@temp_ModelID and CIVersion=@temp_CIVersion
          group by curr.UserID, users.FullName
          ) MachinesSummarized on MachinesSummarized.UserName = users.UserName
          ) TargetsSummarized
          group by
          TargetsSummarized.CI_ModelID,
          TargetsSummarized.CIVersion

          FETCH curs INTO @temp_ModelID, @temp_CIVersion
          END

          CLOSE curs
          DEALLOCATE curs




          select
          @assignmentID as AssignmentID,
          @name as BaselineName,
          @collid as collid,
          AllAssignments.CIVersion as BaselineContentVersion,
          AllAssignments.DisplayName as ParentBaselineDisplayName,
          AllAssignments.CIVersion as ParentBaselineVersion,
          case when AllCIs.CIType_ID<>2 then 0 else 1 end as IsBaseline,
          

          REPLICATE(''-'',3*(AllAssignments.Level)) +  case when (AllAssignments.Level)>0 then ''> '' else ''''  end + case when AllCIs.CIType_ID=2 then AllCIs.DisplayName else AllAssignments.DisplayName end  as SubBaselineDisplayName,
          
          AllCIs.BLDisplayName as SubBaselineName,
          AllAssignments.deepsortorder +  ''-'' + convert(varchar(32),AllCIs.CI_ID) as FinalOrder,
          case when AllCIs.CIType_ID=2 then AllCIs.CIVersion else AllAssignments.CIVersion end as SubBaselineContentVersion,
          case when (AllCIs.RelationType=1 AND  AllCIs.CIType_ID=3) then 2 else AllCIs.RelationType end as BaselinePolicy,
          case when AllCIs.CIType_ID=2 then    2 else AllCIs.CIType_ID end as ConfigurationItemType,
          case when AllCIs.CIType_ID=2 then NULL else AllCIs.DisplayName end as ConfigurationItemName,
          case when AllCIs.CIType_ID=2 then NULL else AllCIs.CIVersion end as CIContentVersion,
          case when AllCIs.CIType_ID=2 then NULL else summary.CountCompliant end as CountCompliant,
          case when AllCIs.CIType_ID=2 then NULL else summary.CountNoncompliant end as CountNoncompliant,
          case when AllCIs.CIType_ID=2 then NULL else summary.FailureCount end as FailureCount,
          case when AllCIs.CIType_ID=2 then NULL else summary.CountEnforced end as CountEnforced,
          case when AllCIs.CIType_ID=2 then NULL else summary.CountNotApplicable end as CountNotApplicable,
          case when AllCIs.CIType_ID=2 then NULL else summary.CountNotDetected end as CountNotDetected,
          case when AllCIs.CIType_ID=2 then NULL else summary.CountUnknown end as CountUnknown,
          case when AllCIs.CIType_ID=2 then NULL else summary.CountReported end as CountReported,
          case when AllCIs.CIType_ID=2 then NULL else summary.CountTargeted end as CountTargeted,
          case when AllCIs.CIType_ID=2 then NULL else summary.Severity end as MaxNoncomplianceCriticality,
          case when AllCIs.CIType_ID=2 then NULL else case when summary.CountReported>0 then convert(numeric(5,2), 100.0*summary.CountCompliant/summary.CountReported) else 0 end end as CompliancePercentage,
          AllCIs.Categories,
          case when AllCIs.CIType_ID=2 then AllCIs.CI_UniqueID else AllAssignments.CI_UniqueID end as SubBaseline_UniqueID,
          case when AllCIs.CIType_ID=2 then AllAssignments.CI_UniqueID else AllCIs.CI_UniqueID end as CI_UniqueID
          from (select distinct CI_UniqueID, CI_ID, CIVersion, deepsortorder, Level, DisplayName from @allassignments) AllAssignments
          inner join @AllCIs AllCIs on AllAssignments.CI_ID=AllCIs.BL_CI_ID
          inner join 
          (  select CI_ModelID,CIVersion,SUM(CountReported) as CountReported,SUM(CountTargeted) as CountTargeted,SUM(CountUnknown) as CountUnknown,SUM(CountCompliant) as CountCompliant,
             SUM(FailureCount) as FailureCount,SUM(CountNoncompliant) as CountNoncompliant,SUM(CountEnforced) as CountEnforced,SUM(CountNotApplicable) as CountNotApplicable,
             SUM(CountNotDetected) as CountNotDetected,MAX(Severity) as Severity
             from @SummarizedCIs
             group by CI_ModelID,CIVersion
          )summary on summary.CI_ModelID=AllCIs.CI_ModelID and summary.CIVersion=AllCIs.CIVersion
          
          where (summary.Severity >= @severity or @severity='''' or @severity is NULL)
          order by
          FinalOrder   
        ',N'@UserSIDs nvarchar(8),@locale nvarchar(5),@name nvarchar(9),@category nvarchar(4000),@collid nvarchar(8),@assignmentID nvarchar(4000),@severity nvarchar(4000)',@UserSIDs=N'16777218',@locale=N'en-US',@name=N'_ Testing',@category=N'',@collid=N'PS100014',@assignmentID=N'',@severity=N''

