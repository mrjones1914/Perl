#!/usr/bin/perl -w
# 
#

my ($bin_file, $bin_file2);


	print "Enter a binary file (i.e. EXE, GIF, JPG, etc) to copy: ";
 	$bin_file = <STDIN>; chomp($bin_file);
	$return = open(BIN, "$bin_file"); binmode(BIN);

 	if(!-B $bin_file)
    {
    	 print "$bin_file does not appear to be a binary file ";
      	 print "; now exiting...\n";
         exit 0;
    }
    else
    {

    	print "Enter a binary file to make backup of => $bin_file: ";
 		$bin_file2 = <STDIN>; chomp($bin_file2);
  		open(BIN2, ">$bin_file2"); binmode(BIN2);
   		
     	if(-e $bin_file2)
     	{
      		#if((!-e $bin_file2))
        #	{
        # 		&copy_BIN(); # Copy the dang file!
        #   }
				
    		&retr();

	if(lc($ans) eq 'y')
	{       

   			if($return)
   			{
   	 			while($file_buff = <BIN>)
     			{
     				print BIN2 $file_buff;
     			}
    
		     close(BIN);
   		     close(BIN2);
   			}
   			else
   			{
	 			die "Could not copy => $!";
   			}
        }
        else
        {
        	&copy_BIN();
        }
    }
    elsif(lc($ans) eq 'n')
    {
    	print "\nExiting...\n";
     	exit 0;
    }
    else
   	{
    	print "Unexpected error...exiting...\n";
     	exit 0;
    }

    }

# Bah, dumb little sub routines...
sub retr()
{
	print "WARNING!: ";
   	print " $bin_file2\'s contents will be overwritten!\n";
   	print "Continue (Y/N): ";
   	$ans = <STDIN>; chomp($ans);
}

sub copy_BIN()
{

	if($return)
	{
		while($file_buff = <BIN>)
		{
			print BIN2 $file_buff;
		}
    
     close(BIN);
     close(BIN2);
	}
	else
	{
		die "Could not copy => $!";
	}
}
