%% Asynchronous decision tree inducer based on ID3
%%
%% Todo:
%%    - allow for numerical attributes (base on c4.5)
%%    - etc.
-module(pid3).
-export([induce/1, induce_branch/5, run/3, test/2]).

-include("nodes.hrl").

-define(INST, ets_inst). % intended to be used for future changes to inst 
-define(MAX_DEPTH, 5). % max branch depth to parallelize
-define(GAIN, async).

%% Induce decision tree from Instances
%% Input:
%%   - From: Pid to process
%%   - Instances: Dictionary with instances
%% Output:
%%   - Decision tree
induce(Instances) ->
    induce(Instances, ?INST:features(Instances), ?MAX_DEPTH).
induce(Instances, Features, M) ->
    case ?INST:stop_induce(Instances, Features) of
	{majority, Class} ->
	    #node{type=classify, value=#classify{as=Class}};
	{dont_stop, N} ->
	    Paralell = if M > 0 -> ?GAIN; true -> sync end,
	    {F, _} = util:min(?INST:gain(Paralell, Features, Instances, N)),
	    S = ?INST:split(F, Instances),
	    Features1 = Features -- [F],
	    Branches = case Paralell of
			   async -> induce_branches(Features1, S, M - 1);
			   sync -> [{Value, induce(Sn, Features1, 0)} || {Value, Sn} <- S]
		       end,

	    #node{type=compare, value=#compare{type=nominal, feature=F, branches=Branches}}
    end.

%% Induce brances for Split
%% Input:
%%    - Features: The features left
%%    - Splits: The Instance set splitted ad Feature
%% Output:
%%    - A list of Two tuples {SplittedValue, Branch}
induce_branches(Features, Splits, M) ->
    Me = self(),
    Pids = [spawn_link(?MODULE, induce_branch, 
		       [Me, Sn, Value, Features, M]) || {Value, Sn} <- Splits],
   
    collect_branches(Me, Pids, []).

%% Induce a brance using Instances
%% Input:
%%    - From: Return result to me
%%    - Instances: The instance set
%%    - Value: The splitted value
%%    - Features: the features to split
%% Output:
%%    From ! {From, self(), {Value, NewBranch}}
induce_branch(From, Instances, Value, Features, M) ->
    From ! {From, self(), {Value, induce(Instances, Features, M)}}.

%% Collect branches induced by Pids
%% Input:
%%    - From: The one how created Pid
%%    - Pids: A list of Pids inducing branches
%%    - Acc: The accumulator
%% Output:
%%    - A list of two tuples {SplittedValue, Branch}
collect_branches(_, [], Acc) ->
    Acc;
collect_branches(From, Pids, Acc) ->
    receive
	{From, Pid, Node} ->
	    collect_branches(From, lists:delete(Pid, Pids), [Node|Acc])    
    end.

run(file, File, N) ->
    Data = ?INST:load(File),
    run(data, Data, N);
run(data, Data, N) ->
    {Test, Train} =  lists:split(round(length(Data) * N), Data),
    {Time, Model} = timer:tc(?MODULE, induce, [Train]),
    Result = lists:foldl(fun (Inst, Acc) -> 
				 [?INST:classify(Inst, Model) == gb_trees:get(class, Inst)|Acc] 
			 end, [], Test),
    Correct = length(lists:filter(fun (X) -> X end, Result)),
    Incorrect = length(lists:filter(fun (X) -> X == false end, Result)),
    {Time, Correct, Incorrect, Correct / (Incorrect + Correct), Result}.

test(data, Data) ->
    {Time, _} = timer:tc(?MODULE, induce, [Data]),
    Time.
