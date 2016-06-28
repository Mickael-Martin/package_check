#!/bin/bash

RESULT="Test_results.log"
BACKUP_HOOKS="conf_ssowat data_home conf_ynh_firewall conf_cron"	# La liste des hooks disponible pour le backup se trouve dans /usr/share/yunohost/hooks/backup/

echo "Chargement des fonctions de testing_process.sh"

source $abs_path/sub_scripts/log_extractor.sh

echo -n "" > $RESULT	# Initialise le fichier des résulats d'analyse

SETUP_APP () {
# echo -e "MANIFEST_ARGS=$MANIFEST_ARGS_MOD"
	COPY_LOG 1
	sudo yunohost --debug app install $APP_CHECK -a "$MANIFEST_ARGS_MOD" > /dev/null 2>&1
	YUNOHOST_RESULT=$?
	COPY_LOG 2
	APPID=$(grep -o "YNH_APP_INSTANCE_NAME=[^ ]*" "$OUTPUTD" | cut -d '=' -f2)	# Récupère le nom de l'app au moment de l'install. Pour pouvoir le réutiliser dans les commandes yunohost. La regex matche tout ce qui suit le =, jusqu'à l'espace.
}

REMOVE_APP () {
	if [ "$auto_remove" -eq 0 ]; then	# Si l'auto_remove est désactivée. Marque une pause avant de continuer.
		read -p "Appuyer sur une touche pour supprimer l'application et continuer les tests..." < /dev/tty
	fi
	ECHO_FORMAT "\nSuppression...\n" "white" "bold"
	COPY_LOG 1
	sudo yunohost --debug app remove $APPID > /dev/null 2>&1
	YUNOHOST_REMOVE=$?
	COPY_LOG 2
}

CHECK_URL () {
	ECHO_FORMAT "\nAccès par l'url...\n" "white" "bold"
	echo "127.0.0.1 $DOMAIN #package_check" | sudo tee -a /etc/hosts > /dev/null	# Renseigne le hosts pour le domain à tester, pour passer directement sur localhost
	curl -LksS $DOMAIN/$CHECK_PATH -o url_output
	URL_TITLE=$(grep "<title>" url_output | cut -d '>' -f 2 | cut -d '<' -f1)
	ECHO_FORMAT "Titre de la page: $URL_TITLE\n" "white"
	if [ "$URL_TITLE" == "YunoHost Portal" ]; then
		YUNO_PORTAL=1
		# Il serait utile de réussir à s'authentifier sur le portail pour tester une app protégée par celui-ci. Mais j'y arrive pas...
	else
		YUNO_PORTAL=0
		ECHO_FORMAT "Extrait du corps de la page:\n" "white"
		echo -e "\e[37m"	# Écrit en light grey
		grep "<body" -A 20 url_output | sed 1d | tee -a $RESULT
		echo -e "\e[0m"
	fi
	sudo sed -i '/#package_check/d' /etc/hosts	# Supprime la ligne dans le hosts
}

CHECK_SETUP_SUBDIR () {
	# Test d'installation en sous-dossier
	ECHO_FORMAT "\n\n>> Installation en sous-dossier...\n" "white" "bold"
	if [ -z "$MANIFEST_DOMAIN" ]; then
		echo "Clé de manifest pour 'domain' introuvable dans le fichier check_process. Impossible de procéder à ce test"
		return
	fi
	if [ -z "$MANIFEST_PATH" ]; then
		echo "Clé de manifest pour 'path' introuvable dans le fichier check_process. Impossible de procéder à ce test"
		return
	fi
	if [ -z "$MANIFEST_USER" ]; then
		echo "Clé de manifest pour 'user' introuvable dans le fichier check_process. Impossible de procéder à ce test"
		return
	fi
	MANIFEST_ARGS_MOD=$MANIFEST_ARGS	# Copie des arguments
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_DOMAIN=[a-Z./-$]*\&/$MANIFEST_DOMAIN=$DOMAIN\&/")
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_PATH=[a-Z/$]*\&@$MANIFEST_PATH=$PATH_TEST\&@")
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_USER=[a-Z/-$]*\&@$MANIFEST_USER=$USER_TEST\&@")
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PASSWORD=[a-Z$]*\&/$MANIFEST_PASSWORD=$PASSWORD_TEST\&/")
	if [ -n "$MANIFEST_PUBLIC" ] && [ -n "$MANIFEST_PUBLIC_public" ]; then	# Si possible, install en public pour le test d'accès url
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PUBLIC=[a-Z]*\&/$MANIFEST_PUBLIC=$MANIFEST_PUBLIC_public\&/")
	fi
	# Installation de l'app
	SETUP_APP
	LOG_EXTRACTOR
	if [ "$YUNOHOST_RESULT" -eq 0 ]; then
		ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
		GLOBAL_CHECK_SETUP=1	# Installation réussie
		GLOBAL_CHECK_SUB_DIR=1	# Installation en sous-dossier réussie
	else
		ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
		if [ "$GLOBAL_CHECK_SETUP" -ne 1 ]; then
			GLOBAL_CHECK_SETUP=-1	# Installation échouée
		fi
		GLOBAL_CHECK_SUB_DIR=-1	# Installation en sous-dossier échouée
	fi
	# Test l'accès à l'app
	CHECK_PATH=$PATH_TEST
	CHECK_URL
	# Suppression de l'app
	REMOVE_APP
	if [ "$YUNOHOST_RESULT" -eq 0 ]	# Si l'installation a été un succès. On teste la suppression
	then
		LOG_EXTRACTOR
		if [ "$YUNOHOST_REMOVE" -eq 0 ]; then
			ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
			GLOBAL_CHECK_REMOVE_SUBDIR=1	# Suppression en sous-dossier réussie
			GLOBAL_CHECK_REMOVE=1	# Suppression réussie
		else
			ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
			if [ "$GLOBAL_CHECK_REMOVE" -ne 1 ]; then
				GLOBAL_CHECK_REMOVE=-1	# Suppression échouée
			fi
			GLOBAL_CHECK_REMOVE_SUBDIR=-1	# Suppression en sous-dossier échouée
		fi
	fi
}

CHECK_SETUP_ROOT () {
	# Test d'installation à la racine
	ECHO_FORMAT "\n\n>> Installation à la racine...\n" "white" "bold"
	if [ -z "$MANIFEST_DOMAIN" ]; then
		echo "Clé de manifest pour 'domain' introuvable dans le fichier check_process. Impossible de procéder à ce test"
		return
	fi
	if [ -z "$MANIFEST_PATH" ]; then
		echo "Clé de manifest pour 'path' introuvable dans le fichier check_process. Impossible de procéder à ce test"
		return
	fi
	if [ -z "$MANIFEST_USER" ]; then
		echo "Clé de manifest pour 'user' introuvable dans le fichier check_process. Impossible de procéder à ce test"
		return
	fi
	MANIFEST_ARGS_MOD=$MANIFEST_ARGS	# Copie des arguments
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_DOMAIN=[a-Z./-$]*\&/$MANIFEST_DOMAIN=$DOMAIN\&/")
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_PATH=[a-Z/$]*\&@$MANIFEST_PATH=/\&@")
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_USER=[a-Z/-$]*\&@$MANIFEST_USER=$USER_TEST\&@")
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PASSWORD=[a-Z$]*\&/$MANIFEST_PASSWORD=$PASSWORD_TEST\&/")
	if [ -n "$MANIFEST_PUBLIC" ] && [ -n "$MANIFEST_PUBLIC_public" ]; then	# Si possible, install en public pour le test d'accès url
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PUBLIC=[a-Z]*\&/$MANIFEST_PUBLIC=$MANIFEST_PUBLIC_public\&/")
	fi
	# Installation de l'app
	SETUP_APP
	LOG_EXTRACTOR
	if [ "$YUNOHOST_RESULT" -eq 0 ]; then
		ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
		GLOBAL_CHECK_SETUP=1	# Installation réussie
		GLOBAL_CHECK_ROOT=1	# Installation à la racine réussie
	else
		ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
		if [ "$GLOBAL_CHECK_SETUP" -ne 1 ]; then
			GLOBAL_CHECK_SETUP=-1	# Installation échouée
		fi
		GLOBAL_CHECK_ROOT=-1	# Installation à la racine échouée
	fi
	# Test l'accès à l'app
	CHECK_PATH="/"
	CHECK_URL
	# Suppression de l'app
	REMOVE_APP
	if [ "$YUNOHOST_RESULT" -eq 0 ]	# Si l'installation a été un succès. On teste la suppression
	then
		LOG_EXTRACTOR
		if [ "$YUNOHOST_REMOVE" -eq 0 ]; then
			ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
			GLOBAL_CHECK_REMOVE_ROOT=1	# Suppression à la racine réussie
			GLOBAL_CHECK_REMOVE=1	# Suppression réussie
		else
			ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
			if [ "$GLOBAL_CHECK_REMOVE" -ne 1 ]; then
				GLOBAL_CHECK_REMOVE=-1	# Suppression échouée
			fi
			GLOBAL_CHECK_REMOVE_ROOT=-1	# Suppression à la racine échouée
		fi
	fi
}

CHECK_SETUP_NO_URL () {
	# Test d'installation sans accès par url
	ECHO_FORMAT "\n\n>> Installation sans accès par url...\n" "white" "bold"
	MANIFEST_ARGS_MOD=$MANIFEST_ARGS	# Copie des arguments
	# Installation de l'app
	SETUP_APP
	LOG_EXTRACTOR
	if [ "$YUNOHOST_RESULT" -eq 0 ]; then
		ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
		GLOBAL_CHECK_SETUP=1	# Installation réussie
	else
		ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
		if [ "$GLOBAL_CHECK_SETUP" -ne 1 ]; then
			GLOBAL_CHECK_SETUP=-1	# Installation échouée
		fi
	fi
	# Suppression de l'app
	REMOVE_APP
	if [ "$YUNOHOST_RESULT" -eq 0 ]	# Si l'installation a été un succès. On teste la suppression
	then
		LOG_EXTRACTOR
		if [ "$YUNOHOST_REMOVE" -eq 0 ]; then
			ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
			GLOBAL_CHECK_REMOVE_ROOT=1	# Suppression réussie
		else
			ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
			if [ "$GLOBAL_CHECK_REMOVE" -ne 1 ]; then
				GLOBAL_CHECK_REMOVE=-1	# Suppression échouée
			fi
			GLOBAL_CHECK_REMOVE_ROOT=-1	# Suppression échouée
		fi
	fi
}

CHECK_UPGRADE () {
	# Test d'upgrade
	ECHO_FORMAT "\n\n>> Upgrade...\n" "white" "bold"
	if [ "$GLOBAL_CHECK_SETUP" -ne 1 ]; then
		echo "L'installation a échouée, impossible d'effectuer ce test..."
		return;
	fi
	MANIFEST_ARGS_MOD=$MANIFEST_ARGS	# Copie des arguments
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_DOMAIN=[a-Z./-$]*\&/$MANIFEST_DOMAIN=$DOMAIN\&/")
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_USER=[a-Z/-$]*\&@$MANIFEST_USER=$USER_TEST\&@")
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PASSWORD=[a-Z$]*\&/$MANIFEST_PASSWORD=$PASSWORD_TEST\&/")
	if [ -n "$MANIFEST_PUBLIC" ] && [ -n "$MANIFEST_PUBLIC_public" ]; then	# Si possible, install en public pour le test d'accès url
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PUBLIC=[a-Z]*\&/$MANIFEST_PUBLIC=$MANIFEST_PUBLIC_public\&/")
	fi
	if [ "$GLOBAL_CHECK_SUB_DIR" -eq 1 ]; then	# Si l'install en sub_dir à fonctionné. Utilise ce mode d'installation
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_PATH=[a-Z/$]*\&@$MANIFEST_PATH=$PATH_TEST\&@")
		CHECK_PATH="$PATH_TEST"
	elif [ "$GLOBAL_CHECK_ROOT" -eq 1 ]; then	# Sinon utilise une install root, si elle a fonctionné
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_PATH=[a-Z/$]*\&@$MANIFEST_PATH=/\&@")
		CHECK_PATH="/"
	else
		echo "Aucun mode d'installation n'a fonctionné, impossible d'effectuer ce test..."
		return;
	fi
	ECHO_FORMAT "\nInstallation préalable...\n" "white" "bold"
	# Installation de l'app
	SETUP_APP
	LOG_EXTRACTOR
	ECHO_FORMAT "\nUpgrade sur la même version du package...\n" "white" "bold"
	# Upgrade de l'app
	COPY_LOG 1
	sudo yunohost --debug app upgrade $APPID -f $APP_CHECK > /dev/null 2>&1
	YUNOHOST_RESULT=$?
	COPY_LOG 2
	LOG_EXTRACTOR
	if [ "$YUNOHOST_RESULT" -eq 0 ]; then
		ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
		GLOBAL_CHECK_UPGRADE=1	# Upgrade réussie
	else
		ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
		GLOBAL_CHECK_UPGRADE=-1	# Upgrade échouée
	fi
	# Test l'accès à l'app
	CHECK_URL
	# Suppression de l'app
	REMOVE_APP
}

CHECK_BACKUP_RESTORE () {
	# Test de backup
	ECHO_FORMAT "\n\n>> Backup...\n" "white" "bold"
	if [ "$GLOBAL_CHECK_SETUP" -ne 1 ]; then
		echo "L'installation a échouée, impossible d'effectuer ce test..."
	fi
	MANIFEST_ARGS_MOD=$MANIFEST_ARGS	# Copie des arguments
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_DOMAIN=[a-Z./-$]*\&/$MANIFEST_DOMAIN=$DOMAIN\&/")
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_USER=[a-Z/-$]*\&@$MANIFEST_USER=$USER_TEST\&@")
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PASSWORD=[a-Z$]*\&/$MANIFEST_PASSWORD=$PASSWORD_TEST\&/")
	if [ -n "$MANIFEST_PUBLIC" ] && [ -n "$MANIFEST_PUBLIC_public" ]; then	# Si possible, install en public pour le test d'accès url
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PUBLIC=[a-Z]*\&/$MANIFEST_PUBLIC=$MANIFEST_PUBLIC_public\&/")
	fi
	if [ "$GLOBAL_CHECK_SUB_DIR" -eq 1 ]; then	# Si l'install en sub_dir à fonctionné. Utilise ce mode d'installation
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_PATH=[a-Z/$]*\&@$MANIFEST_PATH=$PATH_TEST\&@")
		CHECK_PATH="$PATH_TEST"
	elif [ "$GLOBAL_CHECK_ROOT" -eq 1 ]; then	# Sinon utilise une install root, si elle a fonctionné
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_PATH=[a-Z/$]*\&@$MANIFEST_PATH=/\&@")
		CHECK_PATH="/"
	else
		echo "Aucun mode d'installation n'a fonctionné, impossible d'effectuer ce test..."
		return;
	fi
	ECHO_FORMAT "\nInstallation préalable...\n" "white" "bold"
	# Installation de l'app
	SETUP_APP
	LOG_EXTRACTOR
	ECHO_FORMAT "\nBackup de l'application...\n" "white" "bold"
	# Backup de l'app
	COPY_LOG 1
	sudo yunohost --debug backup create -n Backup_test --apps $APPID --hooks $BACKUP_HOOKS > /dev/null 2>&1
	YUNOHOST_RESULT=$?
	COPY_LOG 2
	LOG_EXTRACTOR
	if [ "$YUNOHOST_RESULT" -eq 0 ]; then
		ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
		GLOBAL_CHECK_BACKUP=1	# Backup réussi
	else
		ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
		GLOBAL_CHECK_BACKUP=-1	# Backup échoué
	fi
	# Suppression de l'app
	REMOVE_APP
	ECHO_FORMAT "\nRestauration de l'application...\n" "white" "bold"
	# Restore de l'app
	COPY_LOG 1
	sudo yunohost --debug backup restore Backup_test --force --apps $APPID > /dev/null 2>&1
	YUNOHOST_RESULT=$?
	COPY_LOG 2
	LOG_EXTRACTOR
	if [ "$YUNOHOST_RESULT" -eq 0 ]; then
		ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
		GLOBAL_CHECK_RESTORE=1	# Restore réussi
	else
		ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
		GLOBAL_CHECK_RESTORE=-1	# Restore échoué
	fi
	# Test l'accès à l'app
	CHECK_URL
	# Suppression de l'app
	REMOVE_APP
	# Suppression de l'archive
	sudo yunohost backup delete Backup_test > /dev/null 2>&1
}

CHECK_PUBLIC_PRIVATE () {
	# Test d'installation en public/privé
	if [ "$1" == "private" ]; then
		ECHO_FORMAT "\n\n>> Installation privée...\n" "white" "bold"
	fi
	if [ "$1" == "public" ]; then
		ECHO_FORMAT "\n\n>> Installation publique...\n" "white" "bold"
	fi
	if [ "$GLOBAL_CHECK_SETUP" -ne 1 ]; then
		echo "L'installation a échouée, impossible d'effectuer ce test..."
		return
	fi
	if [ -z "$MANIFEST_PUBLIC" ]; then
		echo "Clé de manifest pour 'is_public' introuvable dans le fichier check_process. Impossible de procéder à ce test"
		return
	fi
	if [ -z "$MANIFEST_PUBLIC_public" ]; then
		echo "Valeur 'public' pour la clé de manifest 'is_public' introuvable dans le fichier check_process. Impossible de procéder à ce test"
		return
	fi
	if [ -z "$MANIFEST_PUBLIC_private" ]; then
		echo "Valeur 'private' pour la clé de manifest 'is_public' introuvable dans le fichier check_process. Impossible de procéder à ce test"
		return
	fi
	MANIFEST_ARGS_MOD=$MANIFEST_ARGS	# Copie des arguments
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_DOMAIN=[a-Z./-$]*\&/$MANIFEST_DOMAIN=$DOMAIN\&/")
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_USER=[a-Z/-$]*\&@$MANIFEST_USER=$USER_TEST\&@")
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PASSWORD=[a-Z$]*\&/$MANIFEST_PASSWORD=$PASSWORD_TEST\&/")
	# Choix public/privé
	if [ "$1" == "private" ]; then
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PUBLIC=[a-Z]*\&/$MANIFEST_PUBLIC=$MANIFEST_PUBLIC_private\&/")
	fi
	if [ "$1" == "public" ]; then
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PUBLIC=[a-Z]*\&/$MANIFEST_PUBLIC=$MANIFEST_PUBLIC_public\&/")
	fi
	if [ "$GLOBAL_CHECK_SUB_DIR" -eq 1 ]; then	# Si l'install en sub_dir à fonctionné. Utilise ce mode d'installation
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_PATH=[a-Z/$]*\&@$MANIFEST_PATH=$PATH_TEST\&@")
		CHECK_PATH="$PATH_TEST"
	elif [ "$GLOBAL_CHECK_ROOT" -eq 1 ]; then	# Sinon utilise une install root, si elle a fonctionné
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_PATH=[a-Z/$]*\&@$MANIFEST_PATH=/\&@")
		CHECK_PATH="/"
	else
		echo "Aucun mode d'installation n'a fonctionné, impossible d'effectuer ce test..."
		return;
	fi
	# Installation de l'app
	SETUP_APP
	# Test l'accès à l'app
	CHECK_URL
	if [ "$1" == "private" ]; then
		if [ "$YUNO_PORTAL" -eq 0 ]; then	# En privé, si l'accès url n'arrive pas sur le portail. C'est un échec.
			YUNOHOST_RESULT=1
		fi
	fi
	if [ "$1" == "public" ]; then
		if [ "$YUNO_PORTAL" -eq 1 ]; then	# En public, si l'accès url arrive sur le portail. C'est un échec.
			YUNOHOST_RESULT=1
		fi
	fi	
	LOG_EXTRACTOR
	if [ "$YUNOHOST_RESULT" -eq 0 ]; then
		ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
		if [ "$1" == "private" ]; then
			GLOBAL_CHECK_PRIVATE=1	# Installation privée réussie
		fi
		if [ "$1" == "public" ]; then
			GLOBAL_CHECK_PUBLIC=1	# Installation publique réussie
		fi
	else
		ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
		if [ "$1" == "private" ]; then
			GLOBAL_CHECK_PRIVATE=-1	# Installation privée échouée
		fi
		if [ "$1" == "public" ]; then
			GLOBAL_CHECK_PUBLIC=-1	# Installation publique échouée
		fi
	fi
	# Suppression de l'app
	REMOVE_APP
}

CHECK_MULTI_INSTANCE () {
	# Test d'installation en multi-instance
	ECHO_FORMAT "\n\n>> Installation multi-instance...\n" "white" "bold"
	if [ "$GLOBAL_CHECK_SETUP" -ne 1 ]; then
		echo "L'installation a échouée, impossible d'effectuer ce test..."
		return
	fi
	MANIFEST_ARGS_MOD=$MANIFEST_ARGS	# Copie des arguments
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_DOMAIN=[a-Z./-$]*\&/$MANIFEST_DOMAIN=$DOMAIN\&/")
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_USER=[a-Z/-$]*\&@$MANIFEST_USER=$USER_TEST\&@")
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PASSWORD=[a-Z$]*\&/$MANIFEST_PASSWORD=$PASSWORD_TEST\&/")
	if [ -n "$MANIFEST_PUBLIC" ] && [ -n "$MANIFEST_PUBLIC_public" ]; then	# Si possible, install en public pour le test d'accès url
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PUBLIC=[a-Z]*\&/$MANIFEST_PUBLIC=$MANIFEST_PUBLIC_public\&/")
	fi
	if [ "$GLOBAL_CHECK_SUB_DIR" -eq 1 ]; then	# Si l'install en sub_dir à fonctionné. Utilise ce mode d'installation
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_PATH=[a-Z/$]*\&@$MANIFEST_PATH=$PATH_TEST\&@")
		CHECK_PATH="$PATH_TEST"
	else
		echo "L'installation en sous-dossier n'a pas fonctionné, impossible d'effectuer ce test..."
		return;
	fi
	# Installation de l'app une première fois
	SETUP_APP
	LOG_EXTRACTOR
	APPID_first=$APPID	# Stocke le nom de la première instance
	CHECK_PATH_first=$CHECK_PATH	# Stocke le path de la première instance
	YUNOHOST_RESULT_first=$YUNOHOST_RESULT	# Stocke le résulat de l'installation de la première instance
	# Installation de l'app une deuxième fois
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_PATH=[a-Z/$]*\&@$MANIFEST_PATH=$PATH_TEST-2\&@")
	CHECK_PATH="$PATH_TEST-2"
	SETUP_APP
	LOG_EXTRACTOR
	if [ "$YUNOHOST_RESULT" -eq 0 ] && [ "$YUNOHOST_RESULT_first" -eq 0 ]; then
		ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
		GLOBAL_CHECK_MULTI_INSTANCE=1	# Installation multi-instance réussie
	else
		ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
		GLOBAL_CHECK_MULTI_INSTANCE=-1	# Installation multi-instance échouée
	fi
	# Test l'accès à la 1ère instance de l'app
	CHECK_PATH=$CHECK_PATH_first
	CHECK_URL
	# Test l'accès à la 2e instance de l'app
	CHECK_PATH="$PATH_TEST-2"
	CHECK_URL
	# Suppression de la 2e app
	REMOVE_APP
	# Suppression de la 1ère app
	APPID=$APPID_first
	REMOVE_APP
}

CHECK_COMMON_ERROR () {
	# Test d'erreur depuis le manifest
	if [ "$1" == "wrong_user" ]; then
		ECHO_FORMAT "\n\n>> Erreur d'utilisateur...\n" "white" "bold"
	fi
	if [ "$1" == "wrong_path" ]; then
		ECHO_FORMAT "\n\n>> Erreur de domaine...\n" "white" "bold"
	fi
	if [ "$1" == "incorrect_path" ]; then
		ECHO_FORMAT "\n\n>> Path mal formé...\n" "white" "bold"
	fi
	if [ "$1" == "port_already_use" ]; then
		ECHO_FORMAT "\n\n>> Port déjà utilisé...\n" "white" "bold"
		if [ -z "$MANIFEST_PORT" ]; then
			echo "Clé de manifest pour 'port' introuvable dans le fichier check_process. Impossible de procéder à ce test"
			return
		fi
	fi
	if [ "$GLOBAL_CHECK_SETUP" -ne 1 ]; then
		echo "L'installation a échouée, impossible d'effectuer ce test..."
		return
	fi
	MANIFEST_ARGS_MOD=$MANIFEST_ARGS	# Copie des arguments
	if [ "$1" == "wrong_path" ]; then	# Force un domaine incorrect
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_DOMAIN=[a-Z./-$]*\&/$MANIFEST_DOMAIN=domain.tld\&/")
	else
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_DOMAIN=[a-Z./-$]*\&/$MANIFEST_DOMAIN=$DOMAIN\&/")
	fi
	if [ "$1" == "wrong_user" ]; then	# Force un user incorrect
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_USER=[a-Z/-$]*\&@$MANIFEST_USER=NO_USER\&@")
	else
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_USER=[a-Z/-$]*\&@$MANIFEST_USER=$USER_TEST\&@")
	fi
	MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PASSWORD=[a-Z$]*\&/$MANIFEST_PASSWORD=$PASSWORD_TEST\&/")
	if [ "$1" == "incorrect_path" ]; then	# Force un path mal formé: Ce sera path/ au lieu de /path
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_PATH=[a-Z/$]*\&@$MANIFEST_PATH=path/\&@")
	else
		if [ "$GLOBAL_CHECK_SUB_DIR" -eq 1 ]; then	# Si l'install en sub_dir à fonctionné. Utilise ce mode d'installation
			MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_PATH=[a-Z/$]*\&@$MANIFEST_PATH=$PATH_TEST\&@")
			CHECK_PATH="$PATH_TEST"
		elif [ "$GLOBAL_CHECK_ROOT" -eq 1 ]; then	# Sinon utilise une install root, si elle a fonctionné
			MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_PATH=[a-Z/$]*\&@$MANIFEST_PATH=/\&@")
			CHECK_PATH="/"
		else
			echo "Aucun mode d'installation n'a fonctionné, impossible d'effectuer ce test..."
			return;
		fi
	fi
	if [ -n "$MANIFEST_PUBLIC" ] && [ -n "$MANIFEST_PUBLIC_public" ]; then	# Si possible, install en public pour le test d'accès url
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s/$MANIFEST_PUBLIC=[a-Z]*\&/$MANIFEST_PUBLIC=$MANIFEST_PUBLIC_public\&/")
	fi
	if [ "$1" == "port_already_use" ]; then	# Force un port déjà utilisé
		MANIFEST_ARGS_MOD=$(echo $MANIFEST_ARGS_MOD | sed "s@$MANIFEST_PORT=[0-9$]*\&@$MANIFEST_PORT=6660\&@")
		sudo yunohost firewall allow Both 6660 > /dev/null 2>&1
	fi
	# Installation de l'app
	SETUP_APP
	LOG_EXTRACTOR
	if [ "$YUNOHOST_RESULT" -eq 0 ]; then	# wrong_user et wrong_path doivent aboutir à échec de l'installation. C'est l'inverse pour incorrect_path et port_already_use.
		if [ "$1" == "wrong_user" ]; then
			ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
			GLOBAL_CHECK_ADMIN=-1	# Installation privée réussie
		fi
		if [ "$1" == "wrong_path" ]; then
			ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
			GLOBAL_CHECK_DOMAIN=-1	# Installation privée réussie
		fi
		if [ "$1" == "incorrect_path" ]; then
			ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
			GLOBAL_CHECK_PATH=1	# Installation privée réussie
		fi
		if [ "$1" == "port_already_use" ]; then
			ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
			GLOBAL_CHECK_PORT=1	# Installation privée réussie
		fi
	else
		if [ "$1" == "wrong_user" ]; then
			ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
			GLOBAL_CHECK_ADMIN=1	# Installation privée échouée
		fi
		if [ "$1" == "wrong_path" ]; then
			ECHO_FORMAT "--- SUCCESS ---\n" "lgreen" "bold"
			GLOBAL_CHECK_DOMAIN=1	# Installation privée échouée
		fi
		if [ "$1" == "incorrect_path" ]; then
			ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
			GLOBAL_CHECK_PATH=-1	# Installation privée échouée
		fi
		if [ "$1" == "port_already_use" ]; then
			ECHO_FORMAT "--- FAIL ---\n" "lred" "bold"
			GLOBAL_CHECK_PORT=-1	# Installation privée échouée
		fi
	fi
	if [ "$1" == "incorrect_path" ] || [ "$1" == "port_already_use" ]; then
		# Test l'accès à l'app
		CHECK_URL
	fi
	# Suppression de l'app
	REMOVE_APP
	if [ "$1" == "port_already_use" ]; then	# Libère le port ouvert pour le test
		sudo yunohost firewall disallow Both 6660 > /dev/null
	fi
}

CHECK_CORRUPT () {
	# Test d'erreur sur source corrompue
	ECHO_FORMAT "\n\n>> Source corrompue après téléchargement...\n" "white" "bold"
	if [ "$GLOBAL_CHECK_SETUP" -ne 1 ]; then
		echo "L'installation a échouée, impossible d'effectuer ce test..."
	fi
echo -n "Non implémenté"
# GLOBAL_CHECK_CORRUPT=0
}
CHECK_DL () {
	# Test d'erreur de téléchargement de la source
	ECHO_FORMAT "\n\n>> Erreur de téléchargement de la source...\n" "white" "bold"
	if [ "$GLOBAL_CHECK_SETUP" -ne 1 ]; then
		echo "L'installation a échouée, impossible d'effectuer ce test..."
	fi
echo -n "Non implémenté"
# GLOBAL_CHECK_DL=0
}
CHECK_FINALPATH () {
	# Test sur final path déjà utilisé.
	ECHO_FORMAT "\n\n>> Final path déjà utilisé...\n" "white" "bold"
	if [ "$GLOBAL_CHECK_SETUP" -ne 1 ]; then
		echo "L'installation a échouée, impossible d'effectuer ce test..."
	fi
echo -n "Non implémenté"
# GLOBAL_CHECK_FINALPATH=0
}

TESTING_PROCESS () {
	# Lancement des tests
	ECHO_FORMAT "\nScénario de test: $PROCESS_NAME\n" "white" "underlined"
	if [ "$setup_sub_dir" -eq 1 ]; then
		CHECK_SETUP_SUBDIR	# Test d'installation en sous-dossier
	fi
	if [ "$setup_root" -eq 1 ]; then
		CHECK_SETUP_ROOT	# Test d'installation à la racine du domaine
	fi
	if [ "$setup_nourl" -eq 1 ]; then
		CHECK_SETUP_NO_URL	# Test d'installation sans accès par url
	fi
	if [ "$upgrade" -eq 1 ]; then
		CHECK_UPGRADE	# Test d'upgrade
	fi
	if [ "$setup_private" -eq 1 ]; then
		CHECK_PUBLIC_PRIVATE private	# Test d'installation en privé
	fi
	if [ "$setup_public" -eq 1 ]; then
		CHECK_PUBLIC_PRIVATE public	# Test d'installation en public
	fi
	if [ "$multi_instance" -eq 1 ]; then
		CHECK_MULTI_INSTANCE	# Test d'installation multiple
	fi
	if [ "$wrong_user" -eq 1 ]; then
		CHECK_COMMON_ERROR wrong_user	# Test d'erreur d'utilisateur
	fi
	if [ "$wrong_path" -eq 1 ]; then
		CHECK_COMMON_ERROR wrong_path	# Test d'erreur de path ou de domaine
	fi
	if [ "$incorrect_path" -eq 1 ]; then
		CHECK_COMMON_ERROR incorrect_path	# Test d'erreur de forme de path
	fi
	if [ "$port_already_use" -eq 1 ]; then
		CHECK_COMMON_ERROR port_already_use	# Test d'erreur de port
	fi
	if [ "$corrupt_source" -eq 1 ]; then
		CHECK_CORRUPT	# Test d'erreur sur source corrompue -> Comment je vais provoquer ça!?
	fi
	if [ "$fail_download_source" -eq 1 ]; then
		CHECK_DL	# Test d'erreur de téléchargement de la source -> Comment!?
	fi
	if [ "$final_path_already_use" -eq 1 ]; then
		CHECK_FINALPATH	# Test sur final path déjà utilisé.
	fi
	if [ "$backup_restore" -eq 1 ]; then
		CHECK_BACKUP_RESTORE	# Test de backup puis de Restauration
	fi
}