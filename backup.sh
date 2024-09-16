#!/bin/sh -l

set -eu

#----------------------------------------
# Initialise the constants
#----------------------------------------
export GITHUB="true" # Required for appleboy/drone-ssh
THEDATE=`date +%d%m%y%H%M`
BACKUP_DIR="backups"
INPUT_PASS=""
EXTRA_SCRIPT=""

#----------------------------------------
# Load the ssh key to docker container
#----------------------------------------
if [ ! -z "$INPUT_KEY" ] && [ "$INPUT_KEY" != "" ]; then
  echo "🔑 Loading the ssh key..."
  mkdir -p $HOME/.ssh
  echo "$INPUT_KEY" > $HOME/.ssh/deploykey
  chmod 0600 $HOME/.ssh/deploykey
  res=$(ssh -i $HOME/.ssh/deploykey -p $INPUT_PORT -o StrictHostKeyChecking=no $INPUT_USERNAME@$INPUT_HOST "echo 'Deploy key is set'")
  if [ "$res" = "Deploy key is set" ]; then
    echo "Deploy key is set"
  else
    echo "Deploy key is not set"
    exit 1
  fi
  echo "Done!! 🍻"
  if [ ! -z "$INPUT_PASSWORD" ] && [ "$INPUT_PASSWORD" != "" ]; then
    INPUT_KEY="" # Hack to save us from Error: can't set password and key at the same time
  fi
else
  echo "😔 key is not set, Please set key."
  exit 1
fi

#----------------------------------------
# Prepare to recipe to backup
#----------------------------------------
echo "🗃️ Backup type: $INPUT_TYPE"

if [ "$INPUT_TYPE" = "db" ]; then
    echo "DB type: $INPUT_DB_TYPE"
    INPUT_DB_HOST="${INPUT_DB_HOST:-localhost}" # Looks like a common variable for all to have

    if [[ -z $INPUT_DB_USER || -z $INPUT_DB_NAME ]]; then
      echo '😔 db_user and db_name is not set, Please specify.'
      exit 1
    fi

    if [[ "$INPUT_DB_USER" = "" || "$INPUT_DB_NAME" = "" ]]; then
      echo '😔 db_user and db_name should not be empty, Please specify.'
      exit 1
    fi

    if [ ! -z "$INPUT_SCRIPT" ] && [ "$INPUT_SCRIPT" != "" ]; then
      EXTRA_SCRIPT="&& $INPUT_SCRIPT"
    fi

    if [ "$INPUT_DB_TYPE" = "mysql" ]; then
      FILENAME=$INPUT_DB_TYPE-$INPUT_DB_NAME.$THEDATE.sql.gz
      INPUT_DB_PORT="${INPUT_DB_PORT:-3306}"

      if [ ! -z "$INPUT_DB_PASS" ] && [ "$INPUT_DB_PASS" != "" ]; then
        INPUT_PASS="-p'$INPUT_DB_PASS'"
      fi

      INPUT_SCRIPT="mysqldump -q -u $INPUT_DB_USER -P $INPUT_DB_PORT $INPUT_PASS $INPUT_ARGS $INPUT_DB_NAME | gzip -9 > $FILENAME ${EXTRA_SCRIPT}"
    elif [ "$INPUT_DB_TYPE" = "mongo" ]; then
      FILENAME=$INPUT_DB_TYPE-$INPUT_DB_NAME.$THEDATE.tgz
      INPUT_DB_PORT="${INPUT_DB_PORT:-27017}"
      INPUT_AUTH_DB="${INPUT_AUTH_DB:-admin}"
      INPUT_ARGS="${INPUT_ARGS} --gzip -o backmon"

      if [ ! -z "$INPUT_DB_PASS" ] && [ "$INPUT_DB_PASS" != "" ]; then
        INPUT_PASS="-p '$INPUT_DB_PASS'"
      fi

      INPUT_SCRIPT="mongodump --port=$INPUT_DB_PORT -d $INPUT_DB_NAME -u $INPUT_DB_USER $INPUT_PASS --authenticationDatabase=$INPUT_AUTH_DB $INPUT_ARGS && tar -cvzf $FILENAME backmon/$INPUT_DB_NAME ${EXTRA_SCRIPT}"
    elif [ "$INPUT_DB_TYPE" = "postgres" ]; then
      FILENAME=$INPUT_DB_TYPE-$INPUT_DB_NAME.$THEDATE.pgsql.gz
      INPUT_DB_PORT="${INPUT_DB_PORT:-5432}"
      INPUT_ARGS="${INPUT_ARGS} -C --column-inserts"
      INPUT_SCRIPT="PGPASSWORD='$INPUT_DB_PASS' pg_dump -U $INPUT_DB_USER -h $INPUT_DB_HOST $INPUT_ARGS $INPUT_DB_NAME | gzip -9 > $FILENAME ${EXTRA_SCRIPT}"
      echo "🚀 Running pg_dump... with $INPUT_SCRIPT"
    fi
    
fi

if [ "$INPUT_TYPE" = "directory" ]; then
    if [ ! -z "$INPUT_DIRPATH" ] && [ "$INPUT_DIRPATH" != "" ]; then
      SLUG=$(echo $INPUT_DIRPATH | sed -r 's/[~\^]+//g' | sed -r 's/[^a-zA-Z0-9]+/-/g' | sed -r 's/^-+\|-+$//g' | tr A-Z a-z)
      FILENAME=$INPUT_TYPE-$SLUG.$THEDATE.tar.gz
      INPUT_SCRIPT="tar -cvzf $FILENAME $INPUT_DIRPATH ${EXTRA_SCRIPT}"
      INPUT_DB_TYPE="directory" # Hack!! to survive from writing extra lines of code
    else
      echo "😔 dir_path is not set, Please specify dir_path."
      exit 1
    fi
fi

if [ -z "$INPUT_SCRIPT" ]; then
  echo "😔 script is not set, Please specify script."
  exit 1
fi
echo "🚀 Running $INPUT_SCRIPT"

#----------------------------------------
# Execute SSH Commands to create backups first
#----------------------------------------
echo "🏃‍♂️ Running commands over ssh..."
ssh -i $HOME/.ssh/deploykey -p $INPUT_PORT -o StrictHostKeyChecking=no $INPUT_USERNAME@$INPUT_HOST $INPUT_SCRIPT
#----------------------------------------
# Rsync the backup files to container
#----------------------------------------
if [ ! -z "$INPUT_DB_TYPE" ] && [ "$INPUT_DB_TYPE" != "" ]; then
  #----------------------------------------
  # CREATE DESTINATION DIR IF NOT EXISTS
  #----------------------------------------
  if [ ! -d ./$BACKUP_DIR/ ]; then
    mkdir $BACKUP_DIR
  fi

  echo "🔄 Copying the $INPUT_DB_TYPE backups... 🗄"
  ssh -i $HOME/.ssh/deploykey -p $INPUT_PORT -o StrictHostKeyChecking=no $INPUT_USERNAME@$INPUT_HOST "ls ./$INPUT_DB_TYPE*" | while read file; do
    scp -i $HOME/.ssh/deploykey -P $INPUT_PORT -o StrictHostKeyChecking=no $INPUT_USERNAME@$INPUT_HOST:"./$file" "./$BACKUP_DIR/"
    ssh -i $HOME/.ssh/deploykey -p $INPUT_PORT -o StrictHostKeyChecking=no $INPUT_USERNAME@$INPUT_HOST "rm ./$file"
  done

  echo "🤔 Whats the location of backups..."
  CURR_DIR=$(pwd)
  echo "$CURR_DIR/$BACKUP_DIR"

  echo "🔍 Show me backups... 😎"
  ls -lFhS ./$BACKUP_DIR/
else
  if [ ! -z "$INPUT_SCRIPT" ] && [ "$INPUT_SCRIPT" != "" ]; then
    echo "Cheers 🍻"
  else
    echo "😔 db_type is not set, Please specify db_type."
    echo "🔄 Unable to Sync the $INPUT_DB_TYPE backups... 🗄"
    exit 1
  fi
fi



