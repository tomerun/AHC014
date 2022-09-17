require 'date'
require 'fileutils'

range = 100
array_size = 10
contest_id = "AHC014"
solver_id = DateTime.now.strftime("%d%H%M")
solver_path = "#{contest_id}/#{solver_id}"
puts "solver_id: #{solver_id}"

args = [
	'batch', 'submit-job',
	'--job-name', 'marathon_tester',
	'--job-queue', 'marathon_tester',
	'--job-definition', 'marathon_tester_cr',
]

if array_size > 1
	args << '--array-properties' << "size=#{array_size}"
end
args << '--container-overrides'

FileUtils.remove_file("solver.zip", force=true)
system("zip -r solver.zip main.cr run.sh", exception: true)
system("aws", "s3", "cp", "solver.zip", "s3://marathon-tester/#{solver_path}/solver.zip", exception: true)


result_path = "#{solver_path}/00"
envs = "environment=[{name=RANGE,value=#{range}},{name=SUBMISSION_ID,value=#{solver_path}},{name=RESULT_PATH,value=#{result_path}}]"
system('aws', *args, envs, exception: true)

# [2, 3, 4, 5].each do |i|
# 		result_path = sprintf("#{solver_path}/%d", i)
# 		envs = "environment=[{name=RANGE,value=#{range}},{name=SUBMISSION_ID,value=#{solver_path}},{name=RESULT_PATH,value=#{result_path}}, {name=GEN_RATIO,value=#{i}}]"
# 		system('aws', *args, envs, exception: true)
# end
