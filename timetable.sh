#!/bin/bash
clear
# %1 is unit year
p_ci_year="$1"
# unit codes

## Create the database
sqlite3 timetable.db "DROP TABLE IF EXISTS unit; DROP TABLE IF EXISTS activity;"
sqlite3 timetable.db "CREATE TABLE IF NOT EXISTS unit( uCode TEXT PRIMARY KEY, uName TEXT); CREATE TABLE IF NOT EXISTS activity(aYear TEXT, aDay TEXT, aSTime TEXT, aFTime TEXT, aLoc TEXT, sDesc TEXT, uCode TEXT, FOREIGN KEY(uCode) REFERENCES unit(uCode));"

### COLLECT DATA AND STORE TO DATABASE ###------------------------------------------------------------------------------------------
printf "Downloading Data "
while read p_unit_cd
do
  printf "..."
  # open and store http response to temp file
  postData="'mode=&p_unit_cd="$p_unit_cd"&p_unit_title=&p_school=&p_ci_sequence_number=&p_ci_year="$p_ci_year"&p_campus=&p_mode=&cmdSubmit=Search'"
  curl --silent 'http://apps.wcms.ecu.edu.au/semester-timetable/lookup' --data $postData > response
  # unit title (I for case-insensitive)
  ut=`cat response | sed -n '/'$p_unit_cd'/I{n;n;p}' | sed 's/<[^>]*>//g' | sed '2!d'`
  
  ### Insert unit to the database ###
  sqlite3 timetable.db "INSERT INTO unit(uCode, uName) VALUES ('$p_unit_cd', '$ut');"
  
  if [ `echo $ut | wc -w` -gt 0 ]
  then
    # Activities hyperlink (load activities http response to temp file)
    actLink=`cat response | grep ">Activities</a" | sed 's/<td><a href="//g' | sed 's/">Activities<\/a><\/td>//g'`
    curl --silent $actLink > act_response

   ### In Activities ###
    sDesc=`cat act_response | grep -C 1 "<h3>Semester Timetable" | awk 'NR==3' | sed 's/<p><a name="top"><\/a><strong>//g' | sed 's/<font color="red"> &nbsp;&nbsp;//g' | sed 's/<\/font><\/strong><\/p>//g'`

    ## number of Activities ##
    let totAct="`cat act_response | grep '<td valign="top" >' | wc -l` / 6"

    ########## LOOP ACTIVITIES ############
    for (( i=0 ; i<$totAct ; i++ ))
    do
      printf "..."
      # Activity Day
      aDay=`cat act_response | grep '<td valign="top" >' | awk 'NR=='2+$i*6'{print $3}' | sed  's/>//g' | sed 's/<\/td//g'`
      aSTime=`cat act_response | grep '<td valign="top" >' | awk 'NR=='3+$i*6'{print $3}' | sed 's/>//g'`
      aFTime=`cat act_response | grep '<td valign="top" >' | awk 'NR=='3+$i*6'{print $5}' | sed 's/<\/td>//g'`
      aLoc=`cat act_response | grep '<td valign="top" >' | awk 'NR=='4+$i*6 | sed "s/<a href='http:\/\/www.ecu.edu.au\/fas\/map\/view.php?//g" | sed 's/<td valign="top" >//g' | sed 's/<\/a><\/td>//g' | sed "s/'>/  /g"`

      ### Insert activity to the database ###
      sqlite3 timetable.db "INSERT INTO activity (aYear, aDay, aSTime, aFTime, aLoc, sDesc, uCode) values ('$p_ci_year', '$aDay', '$aSTime', '$aFTime', '$aLoc', '$sDesc', '$p_unit_cd')"
    done

  else
    sqlite3 timetable.db "UPDATE unit SET uName = '** NO RESULTS FOUND FOR UNIT CODE **' WHERE uCode = '$p_unit_cd';"
  fi
done
printf "Done!\n"

### RETRIVE DATA FROM DATABASE AND PRINT TO SCREEN ###-------------------------------------------------------------------------
uCount=`sqlite3 timetable.db "SELECT Count(*) FROM unit"`

printf "\n----------------------\n"

for (( i=0 ; i<$uCount ; i++ ))
do
  # retrieve unit code and title from row i in unit
  uCode=`sqlite3 timetable.db "SELECT upper(uCode) FROM unit ORDER BY uCode LIMIT 1 OFFSET $i"`
  uName=`sqlite3 timetable.db "SELECT uName FROM unit ORDER BY uCode LIMIT 1 OFFSET $i"`
  # Print unit name
  printf "UnitCode: %s\n" "$uCode"
  printf "Title: %s\n" "$uName"

  # get activity count for FK unit code
  aCount=`sqlite3 timetable.db "SELECT Count(*) FROM activity WHERE uCode = '$uCode' COLLATE NOCASE"`
  sDesc=`sqlite3 timetable.db "SELECT sDesc FROM activity WHERE uCode = '$uCode' COLLATE NOCASE LIMIT 1 OFFSET $i"`
  printf "Desc: %s\n" "$sDesc"

  # Loop activity 
  for (( j=0 ; j<$aCount ; j++ ))
  do
    aDay=`sqlite3 timetable.db "SELECT aDay FROM activity WHERE uCode = '$uCode' COLLATE NOCASE LIMIT 1 OFFSET $j"`
    aSTime=`sqlite3 timetable.db "SELECT aSTime FROM activity WHERE uCode = '$uCode' COLLATE NOCASE LIMIT 1 OFFSET $j"`
    aFTime=`sqlite3 timetable.db "SELECT aFTime FROM activity WHERE uCode = '$uCode' COLLATE NOCASE LIMIT 1 OFFSET $j"`
    aLoc=`sqlite3 timetable.db "SELECT aLoc FROM activity WHERE uCode = '$uCode' COLLATE NOCASE LIMIT 1 OFFSET $j"`
    printf "\t%s  (%s ->- %s)\n" "$aDay" "$aSTime" "$aFTime"
    printf "\t\t--Location: %s\n" "$aLoc"
  done
  printf "\n----------------------\n"
done

## Clean up ## 
rm response
rm act_response

