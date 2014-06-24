#!/bin/sh

# Build script to build and package the
# development builds for both iOS and
# Simulator platforms for Debug and Release
# R.Rampley - mok9

projpath="./TheAmazingAudioEngine.xcodeproj"
projtarg="TheAmazingAudioEngine"

declare -a buildconfigs=(	"Debug"
									"Release" );

# this will need to be updated each time the SDK is updated
declare -a buildplatforms=(	"iphonesimulator7.1"
										"iphoneos7.1" );

# lipo values give us a final sanity check that we have the 
# architectures we are expecting to find in each build
declare -a lipovals=(	"./build/Debug-iphoneos/libTheAmazingAudioEngine.a"
								"./build/Debug-iphonesimulator/libTheAmazingAudioEngine.a"
								"./build/Debug-universal/libTheAmazingAudioEngine.a"
								"./build/Release-iphoneos/libTheAmazingAudioEngine.a"
								"./build/Release-iphonesimulator/libTheAmazingAudioEngine.a"
								"./build/Release-universal/libTheAmazingAudioEngine.a" );

# Test App Project - build this to validate linking
tapppath="./TheEngineSample.xcodeproj"
tapptarg="TheEngineSample"

sclns=

exiterr()
{
   echo "ERROR $1"
	exit $1
}


echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

echo "Building $projname"
echo "Be sure your Xcode Select is correct"
xcph=`xcode-select -print-path`
xbvr=`xcodebuild -version`

echo "xcode-select (PATH)=\n\t\"$xcph\""
echo "xcodebuild-version=\n\t\"$xbvr\""
	
	echo "."
	echo "Enter to continue, Ctl+C to Quit"
	read nothing

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "CLEANING PROJECTS"

	for cfg in "${buildconfigs[@]}"
	do
		for plt in "${buildplatforms[@]}"
		do
			echo "........................................................"
			echo "LIB Cleaning $cfg - $plt"

			xcodebuild -project ${projpath} -target ${projtarg} -sdk ${plt} -configuration ${cfg} clean

			sclns=$?
			echo ". $sclns"
			if [ "$sclns" -ne "0" ] ; then
				exiterr $sclns
			fi
			echo "........................................................"

			xcodebuild -project ${tapppath} -target ${tapptarg} -sdk ${plt} -configuration ${cfg} clean

			sclns=$?
			echo ". $sclns"
			if [ "$sclns" -ne "0" ] ; then
				exiterr $sclns
			fi
			echo "........................................................"
		done
	done

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "BUILDING LIB PROJECTS"

	for cfg in "${buildconfigs[@]}"
	do
		for plt in "${buildplatforms[@]}"
		do
			echo "........................................................"
			echo "LIB Building $cfg - $plt"
			echo "........................................................"

			xcodebuild -project ${projpath} -target ${projtarg} -sdk ${plt} -configuration ${cfg} build

			sclns=$?
			echo ". $sclns"
			if [ "$sclns" -ne "0" ] ; then
				exiterr $sclns
			fi
			echo "........................................................"
		done
	done

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "BUILDING TEST APP"

	for cfg in "${buildconfigs[@]}"
	do
		for plt in "${buildplatforms[@]}"
		do
			echo "........................................................"
			echo "LIB Building $cfg - $plt"
			echo "........................................................"

			xcodebuild -project ${tapppath} -target ${tapptarg} -sdk ${plt} -configuration ${cfg} build

			sclns=$?
			echo ". $sclns"
			if [ "$sclns" -ne "0" ] ; then
				exiterr $sclns
			fi
			echo "........................................................"
		done
	done

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "LIPO VALIDATING LIB BUILDS"

	for trg in "${lipovals[@]}"
	do
			echo "........................................................"
			echo "lipo check $trg"

			lipo -info ${trg}
			sclns=$?
			echo ". $sclns"
			if [ "$sclns" -ne "0" ] ; then
				exiterr $sclns
			fi
	done


echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
exit 0
