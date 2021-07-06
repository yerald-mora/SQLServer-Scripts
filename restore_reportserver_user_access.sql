Use ReportServer
--DROP TABLE #Users
CREATE TABLE #Users (Usuario varchar(30),DomainUser varchar(30),RSUser varchar(30),DomainUserSid varbinary(MAX), RSUserSid varbinary(MAX),NewGroupUserId varchar(80),CurrentGroupUserId varchar(80))
CREATE TABLE #UsersToDelete(UserId uniqueidentifier)
CREATE TABLE #UserPolicies(SecDataId uniqueidentifier, XmlDescription nvarchar(max), xmlPolicy xml, GroupUserName varchar(80), GroupUserId varchar(80))

/*CREATE USER DATA IN VARBINARY AND BASE64*/
;WITH U
AS
(	--basically a table of users with the sid and domain user name
	SELECT cod_usuario Usuario		
		,SUSER_SID('Domain\' + username)DomainUserSid
		,'Domain\' + username DomainUser
	FROM Mydb.myschema.myusertable ut
	WHERE ut.status = 1
)
INSERT INTO #Users
SELECT Usuario
	,DomainUser
	,UserName RSUser
	, DomainUserSid
	,Sid RSUserSid
	, CAST('' as xml).value('xs:base64Binary(sql:column("U.DomainUserSid"))','varchar(80)') NewGroupUserId
	, CAST('' as xml).value('xs:base64Binary(sql:column("U2.Sid"))','varchar(80)') CurrentGroupUserId
FROM U JOIN Users U2 ON UPPER(UserName) COLLATE SQL_Latin1_General_CP1_CS_AS like '%'+U.Usuario+'%' COLLATE SQL_Latin1_General_CP1_CS_AS

/*Search for inactive and repetead user that shouldn't have access*/
INSERT INTO #UsersToDelete
SELECT UserID 
FROM Users U LEFT JOIN
	(
	SELECT DomainUser,MAX(RSUserSid) Sid
	FROM #Users
	GROUP BY DomainUser
	)U2 ON U.Sid = U2.Sid
WHERE U2.Sid IS NULL and UserName not in('NT AUTHORITY\SYSTEM','BUILTIN\Administrators')

/*Assgin all object to an existant userid (select an userid from Users table, it should be an administrator)*/
UPDATE C set CreatedByID = '0D91E289-F64C-4F7A-95F0-7ACC26D1F9AF' ,ModifiedByID='0D91E289-F64C-4F7A-95F0-7ACC26D1F9AF' 
FROM Catalog C JOIN #UsersToDelete U ON C.CreatedByID = U.UserId OR C.ModifiedByID = U.UserId

UPDATE Subscriptions SET OwnerID = '0D91E289-F64C-4F7A-95F0-7ACC26D1F9AF'
UPDATE Schedule SET CreatedById = '0D91E289-F64C-4F7A-95F0-7ACC26D1F9AF'

/*Delete users*/
UPDATE S SET ModifiedByID = OwnerID FROM Subscriptions S JOIN #UsersToDelete U ON S.ModifiedByID = U.UserId
DELETE S FROM Subscriptions S JOIN #UsersToDelete U ON S.OwnerID = U.UserId
DELETE S FROM Schedule S JOIN #UsersToDelete U ON S.CreatedById = U.UserId
DELETE P FROM PolicyUserRole P JOIN #UsersToDelete U ON P.UserID = U.UserId
DELETE U FROM Users U JOIN #UsersToDelete U2 ON U.UserID = U2.UserId

/*Update user sid to match the users sid from the new domain*/
UPDATE U SET U.Sid = U2.DomainUserSid, UserName = Usuario FROM Users U JOIN #Users U2 on U.Sid = U2.RSUserSid

/*Replace GroupUserName and GroupUserId en XmlDescription that contains the access policies*/
;WITH D
AS
(
SELECT SecDataID,CAST(XmlDescription as varchar(max)) XmlDescription,Cast(XmlDescription as xml) xmlpolicy FROM SecData
)
INSERT INTO #UserPolicies
SELECT SecDataID,XmlDescription,xmlpolicy
	,p.value('GroupUserName[1]','nvarchar(100)')
	,p.value('GroupUserId[1]','nvarchar(100)')
FROM D CROSS APPLY D.xmlpolicy.nodes('/Policies/Policy') as [Policy](p)

DECLARE @SecDataId uniqueidentifier
	,@GroupUserName varchar(80)
	,@GroupUserId varchar(80)
	,@NewGroupUserName varchar(80)
	,@NewGroupUserId varchar(80)

DECLARE cur_policies CURSOR FOR
	SELECT SecDataId,GroupUserName,GroupUserId,Usuario,NewGroupUserId
	FROM #UserPolicies UP 
		JOIN #Users U ON UP.GroupUserId = U.CurrentGroupUserId
OPEN cur_policies
FETCH cur_policies INTO @SecDataId,@GroupUserName,@GroupUserId,@NewGroupUserName,@NewGroupUserId
WHILE @@FETCH_STATUS = 0
BEGIN
	UPDATE SecData SET XmlDescription = REPLACE(REPLACE(CAST(XmlDescription as varchar(max)),@GroupUserId,@NewGroupUserId),@GroupUserName,@NewGroupUserName)
	WHERE SecDataID = @SecDataId
	FETCH cur_policies INTO @SecDataId,@GroupUserName,@GroupUserId,@NewGroupUserName,@NewGroupUserId
END
CLOSE cur_policies
DEALLOCATE cur_policies

SELECT * FROM Users
